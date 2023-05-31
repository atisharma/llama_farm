"
Parse user input and dispatch the resulting operation,
either internally or to a chatbot / langchain.
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import os)
(import shlex)
(import logging)

(import llama-farm [ask store])
(import .models [bots model params reply])
(import .documents [tokenizer chat->docs])
(import .utils [config slurp is-url msg system inject user])
(import .texts [now->text today->text])
(import .interface [banner
                    bot-color
                    clear
                    clear-status-line
                    console
                    error
                    format-sources
                    get-margin
                    info
                    print-chat-history
                    print-message
                    print-sources
                    set-width
                    spinner-context
                    status-line
                    tabulate
                    toggle-markdown])

(import requests.exceptions [MissingSchema ConnectionError])
(import youtube-transcript-api._errors [TranscriptsDisabled])


;; TODO: separate calls for text summary insertion and chat-over-docs for (e.g.) wikipedia, arxiv, yt, file
;; TODO: status-line: history (tokens) | model | current-topic | current tool

;; TODO: remove global state for current topic and context.
(setv bot (get (bots) 0)
      current-topic "No topic is set yet."
      context "")

;; TODO: test with Chroma, present an option in the config
(setv knowledge-store (store.faiss (os.path.join (config "storage" "path")
                                                 "knowledge.faiss")))

(setv chat-store (store.faiss (os.path.join (config "storage" "path")
                                            "chat.faiss")))

(setv help-str (slurp (or (+ (os.path.dirname __file__) "/help.md")
                          "llama_farm/help.md")))

;;; -----------------------------------------------------------------------------
;;; functions for internal use
;;; -----------------------------------------------------------------------------

(defn _ingest [df files-or-url]
  "A convenience wrapper."
  (try
    (for [f (shlex.split files-or-url)]
      (if (is-url f)
        (store.ingest-urls knowledge-store f)
        (store.ingest-files knowledge-store f))) 
    (info "Done.")
    (except [e [ConnectionError]]
      (error f"I can't find that URL.
`{(repr e)}`"))
    (except [e [FileNotFoundError]]
      (error f"I can't find that file or directory.
`{(repr e)}`"))))

(defn _list-bots []
  "Tabulate the available bots."
  (info "The following bots are available.")
  (tabulate
    :rows (lfor p (bots)
                (let [name f"{(.capitalize p)}" 
                      kind (:kind (params p) "fake")
                      model (:model_name (params p) "")
                      temp (:temperature (params p) "")
                      system-prompt (:system-prompt (params p) "")]
                  [name kind model (str temp) system-prompt]))
    :headers ["bot" "kind" "model" "temp" "system prompt"]
    :styles (list (map bot-color (bots)))))

(defn set-bot [[new-bot ""]]
  (global bot)
  (let [p (.lower new-bot)]
    (info
      (cond (in p (bots)) (do (setv bot p)
                              f"*You are now talking to {(.title bot)}.*")
            (not p) f"*You are talking to {(.title bot)}.*"
            :else f"*{p} is not available. You are still talking to {(.title bot)}.*")))) 
  
;;; -----------------------------------------------------------------------------
;;; chat management
;;; -----------------------------------------------------------------------------

(defn token-count [x]
  "The number of tokens, roughly, of a chat history (or anything with a meaningful __repr__)."
  (->> x
       (str)
       (tokenizer.encode)
       (len)))

(defn truncate [bot system-prompt chat-history]
  "Shorten the chat history if it gets too long.
   Split it in two and store the first part in the chat store.
   Set a new context.
   Return the new chat history."
  (global context current-topic)
  (let [truncation-length (:truncation-length (params bot) 1000)
        token-length (token-count (inject system-prompt chat-history))
        chat-length (len chat-history)]
    (if (and (> token-length truncation-length)
             (> (len chat-history) 12))
      (let [pre (cut chat-history 8)
            post (cut chat-history 8 None)]
        (commit-chat bot pre)
        (setv current-topic (topic bot pre))
        (setv context (recall chat-store bot current-topic))
        post)
      chat-history)))

(defn commit-chat [bot chat]
  "Save a chat history fragment to the chat store."
  (let [chat-topic (topic bot chat)
        docs (chat->docs chat chat-topic)]
    (store.ingest-docs chat-store docs)))

(defn recall [db bot topic]
  "Summarise a topic from a memory store (usually the chat).
   Return as text which may then be used for injection in the system message."
  (let [username (or (.lower (config "user")) "user")
        query f"{topic}\n{bot}:\n{username}:"
        k (or (config "storage" "sources") 6)
        docs (store.similarity db query :k k)
        chat-str (.join "\n" (lfor d docs f"{(:time d.metadata)}\n{d.page-content}"))]
    (ask.summarize (model bot) chat-str))) 

(defn topic [bot chat-history]
  "Determine the current topic of conversation from the chat history."
  (let [username (or (config "user") "user")
        topic-msg (user "Please summarize the conversation so far in less than ten words." username)
        topic-reply (reply bot (inject "Your sole purpose is to express the topic of conversation in one short sentence."
                                       (+ chat-history [topic-msg])))]
    (:content topic-reply)))

;;; -----------------------------------------------------------------------------
;;; Enquiry functions: query ... -> message pair
;;; -----------------------------------------------------------------------------

;; TODO: abstract out boilerplate here

(defn enquire-db [bot user-message args chat-history * chain-type]
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          reply (ask.chat-db knowledge-store
                             (model bot)
                             args
                             (cut chat-history -6 None)
                             :chain-type chain-type
                             :sources True
                             :search-kwargs {"k" (or (config "storage" "sources") 6)})]
      (print-sources (:source-documents reply))
      (let [reply-msg (msg "assistant" f"{(:answer reply)}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"[Knowledge query] {args}"} reply-msg]))))

(defn enquire-wikipedia [bot user-message args chat-history * chain-type]
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          reply (ask.chat-wikipedia (model bot)
                                    args
                                    (cut chat-history -6 None)
                                    :chain-type chain-type
                                    :sources True)]
      (let [reply-msg (msg "assistant" f"{(:answer reply)}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"[Wikipedia query] {args}"} reply-msg]))))

(defn enquire-arxiv [bot user-message args chat-history * chain-type]
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          reply (ask.chat-arxiv (model bot)
                                args
                                (cut chat-history -6 None)
                                :chain-type chain-type
                                :sources True)]
                                ;:load-max-docs (config "storage" "arxiv_max_docs"))]
      (let [reply-msg (msg "assistant" f"{(:answer reply)}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"[ArXiv query] {args}"} reply-msg]))))

;; TODO: use file, url and youtube retrievers here when they are finished.
;; or, work out how to chat over docs directly.

(defn enquire-summarize-url [bot user-message url chat-history]
  "Summarize a URL."
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          summary (ask.summarize-url (model bot) url)]
      (let [reply-msg (msg "assistant" f"{summary}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"Summarize the webpage {url}"} reply-msg]))))

(defn enquire-summarize-youtube [bot user-message youtube-id chat-history]
  "Summarize a Youtube video (transcript)."
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          summary (ask.summarize-youtube (model bot) youtube-id)]
      (let [reply-msg (msg "assistant" f"{summary}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"Summarize the Youtube video [{youtube-id}](https://www.youtube.com/watch?v={youtube-id})"} reply-msg]))))

;;; -----------------------------------------------------------------------------
;;; The parser: message, list[message] -> message | None
;;; -----------------------------------------------------------------------------

(defn parse [user-message chat-history]
  "Take as input user-message: {role: user, content: line}, the chat history: [list messages], and bot: (system prompt string).
   Do the action resulting from `line`, and return the updated chat history."
  (global bot context current-topic)
  (clear-status-line)
  (let [chain-type (or (config "chain-type") "stuff")
        bot-prompt (:system_prompt (params bot) "")
        bot-name (.capitalize bot)
        time-prompt f"Today's date and time is {(now->text)}."
        system-prompt f"{time-prompt}\n{bot-prompt}\nThe user's name is {(:bot user-message)}.\n{context}"
        line (:content user-message)
        margin (get-margin chat-history)
        [_command _ args] (.partition line " ")
        command (.lower _command)]
    (unless (.startswith line "/")
      (setv chat-history (truncate bot system-prompt chat-history))
      (.append chat-history user-message))
    (cond
      ;; commands that give a reply
      ;;
      ;; move this to a function, and call with different chain-types, k, search type.
      (= command "/ask") (.extend chat-history
                                  (enquire-db
                                    bot
                                    user-message
                                    args
                                    (inject system-prompt chat-history)
                                    :chain-type chain-type))
      (= command "/wikipedia") (.extend chat-history
                                        (enquire-wikipedia
                                          bot
                                          user-message
                                          args
                                          (inject system-prompt chat-history)
                                          :chain-type chain-type))
      (= command "/arxiv") (.extend chat-history
                                    (enquire-arxiv
                                      bot
                                      user-message
                                      args
                                      (inject system-prompt chat-history)
                                      :chain-type chain-type))
      (= command "/url") (try
                           (.extend chat-history (enquire-summarize-url bot
                                                                        user-message
                                                                        args
                                                                        (inject system-prompt chat-history)))
                           (except [e [MissingSchema ConnectionError]]
                             (error f"I can't get anything from [{args}]({args})")))
      (= command "/youtube") (try
                               (.extend chat-history
                                        (enquire-summarize-youtube bot
                                                                   user-message
                                                                   args
                                                                   (inject system-prompt chat-history)))
                               (except [TranscriptsDisabled]
                                 (error f"I can't find a transcript for [{args}](https://www.youtube.com/watch/?v={args})")))
      ;;
      ;; interface commands
      (= command "/clear") (clear)
      (= command "/banner") (do (clear) (banner) (console.rule))
      (= command "/width") (set-width line)
      (= command "/markdown") (toggle-markdown)
      (= command "/reset!") (do (info "Conversation discarded.")
                                (setv chat-history []))
      (= command "/undo") (setv chat-history (cut chat-history 0 -2))
      (in command ["/h" "/help"]) (info help-str)
      (= command "/version") (info (version "llama_farm"))
      ;;
      ;; bot / chat commands
      (= command "/bot") (do (set-bot args) (setv bot-name (.capitalize bot)))
      (= command "/bots") (_list-bots)
      (in command ["/history" "/hist"]) (print-chat-history chat-history
                                                            :tokens (token-count (inject system-prompt chat-history)))
      ;;
      ;; vectorstore commands
      (= command "/ingest") (_ingest knowledge-store args)
      (= command "/sources") (info (format-sources (store.mmr knowledge-store args)))
      (= command "/recall") (info (recall chat-store bot args))
      (= command "/topic") (if args
                               (setv current-topic args)
                               (with [c (spinner-context f"{bot-name} is summarizing...")]
                                 (setv current-topic (topic bot chat-history))
                                 (info current-topic)))
      (= command "/context") (with [c (spinner-context f"{bot-name} is summarizing...")]
                               (setv context (recall chat-store bot current-topic))
                               (info context))
      (= command "/system") (info system-prompt)
      ;;
      (.startswith line "/") (error f"Unknown command **{command}**.")
      ;;
      ;; otherwise, normal chat
      :else (with [c (spinner-context f"{bot-name} is thinking...")]
              (let [reply-msg (reply bot (inject system-prompt chat-history))]
                (.append chat-history reply-msg)
                (print-message reply-msg margin))))
    ;;
    (status-line f"[{(bot-color bot)}]{bot-name}[default] | [green]{(token-count (inject system-prompt chat-history))} tkns | {current-topic}")
    chat-history))
