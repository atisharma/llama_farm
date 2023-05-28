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
(import .utils [config is-url msg system inject user])
(import .texts [now->text])
(import .interface [banner
                    bot-color
                    clear
                    console
                    error
                    get-margin
                    info
                    info
                    print-chat-history
                    print-message
                    print-sources
                    set-width
                    spinner-context
                    tabulate
                    toggle-markdown])

(import requests.exceptions [MissingSchema ConnectionError])
(import youtube-transcript-api._errors [TranscriptsDisabled])


;; TODO: separate calls for text summary insertion and chat-over-docs for (e.g.) wikipedia, arxiv, yt, file
;; TODO: measure chat-history length in tokens and drop to chat store old comments as conversation.
;; TODO: determine current topic over last N messages, and inject that as context to search chat store.
;; TODO: status-line: history (tokens) | model | current-topic | current tool

;; TODO: remove global state for current topic and context.
(setv bot (get (bots) 0)
      current-topic "No topic set yet."
      context "")

(setv knowledge-store (store.faiss (os.path.join (config "storage" "path")
                                                 "knowledge.faiss")))

(setv chat-store (store.faiss (os.path.join (config "storage" "path")
                                            "chat.faiss")))

(setv help-str "
To chat, just enter some text.

Lines beginning with **/** are parsed as commands.  
The usual readline shortcuts should be available.

#### Commands

- **/help /h**                      Show this helpful text
- **/quit /q /exit**                Quit
- **/version**                      Show the version of this client
- **/clear**                        Clear the display
- **/markdown**                     Toggle markdown rendering of messages

#### Bots

- **/bots /personalities**          List the available bots
- **/bot /personality /p**          Show the current bot to whom input goes
- **/bot 'name'**                   Start talking to a particular bot

#### Conversation

- **/undo**                         Delete the last two items in the conversation
- **/retry**                        Get a new response to the last input
- **/history**                      Print the whole chat history for this session
- **/reset!**                       Discard the whole chat history from this session

### Query

- **/ask 'query'**                  Ask a question over the knowledge store
- **/wikipedia 'query'**            Ask a question with reference to wikipedia
- **/arxiv 'query'**                Ask a question with access to arXiv

### Summarize

- **/youtube 'youtube-id'**         Summarize a Youtube video
- **/url 'https://example.com'**    Summarize example.com

#### Knowledge management

- **/recall**                       Make a query against the bot's long-term memory
- **/ingest 'filename(s)'**         Ingest a filename, list of filenames (separated by spaces, no quotes), or directory (recursively) to the knowledge store  
- **/ingest 'urls(s)'**             Ingest a webpage at a single url or list of urls (separated by spaces, no quotes)
")

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
  "The number of tokens, roughly, of a chat history."
  (->> x
       (str)
       (tokenizer.encode)
       (len)))

(defn remember [bot chat-history]
  "Shorten the chat history if it gets too long.
   Split it in two and store the first part in the chat store.
   Set a new context.
   Return the new chat history."
  (global context current-topic)
  (with [c (spinner-context f"{(.capitalize bot)} is rembering the conversation...")]
    (let [context-length (:context-length (params bot) 1250)
          token-length (token-count chat-history)
          chat-length (len chat-history)]
      (if (and (> token-length context-length)
               (> (len chat-history) 12))
        (let [pre (cut chat-history 8)
              post (cut chat-history 8 None)
              pre-topic (topic bot pre)
              docs (chat->docs pre pre-topic)]
          (store.ingest-docs chat-store docs)
          (setv current-topic (topic bot pre))
          (setv context (recall chat-store bot current-topic))
          post)
        chat-history))))

(defn recall [db bot topic]
  "Summarise a topic from a memory store (usually the chat).
   Return for injection as a system message."
  (let [username (or (config "repl" "user") "user")
        query f"{topic}\n{bot}: {username}:"
        k (or (config "storage" "sources") 6)
        docs (store.similarity db query :k k)
        chat-str (.join "\n" (lfor d docs f"{(:time d.metadata)}\n{d.page-content}"))]
    (ask.summarize (model bot) chat-str))) 

(defn topic [bot chat-history]
  "Determine the current topic of conversation from the chat history."
  (let [username (or (config "repl" "user") "user")
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
        [{#** user-message "content" f"[Database query] {args}"} reply-msg]))))

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
  (let [chain-type (or (config "repl" "chain-type") "stuff")
        bot-prompt (:system_prompt (params bot) "")
        time-prompt f"Today's date and time is {(now->text)}."
        system-prompt f"{time-prompt}\n{bot-prompt}\n{context}"
        line (:content user-message)
        margin (get-margin chat-history)
        [_command _ args] (.partition line " ")
        command (.lower _command)]
    (unless (.startswith line "/")
      (setv chat-history (remember bot chat-history))
      (.append chat-history user-message))
    (cond
      ;; commands that give a reply
      ;;
      ;; move this to a function, and call with different chain-types, k, search type.
      (= command "/ask") (.extend chat-history (enquire-db bot user-message args (inject system-prompt chat-history)
                                                           :chain-type chain-type))
      (= command "/wikipedia") (.extend chat-history (enquire-wikipedia bot user-message args (inject system-prompt chat-history)
                                                                        :chain-type chain-type))
      (= command "/arxiv") (.extend chat-history (enquire-arxiv
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
      (= command "/help") (info help-str)
      (= command "/h") (info help-str)
      (= command "/version") (info (version "llama_farm"))
      ;;
      ;; bot / chat commands
      (= command "/bot") (set-bot args)
      (= command "/bots") (_list-bots)
      (= command "/personalities") (_list-bots)
      (= command "/history") (print-chat-history chat-history :tokens (token-count chat-history))
      ;;
      ;; vectorstore commands
      (= command "/ingest") (_ingest knowledge-store args)
      ;(= command "/remember") (setv chat-history (remember bot chat-history))
      (= command "/recall") (info (recall chat-store bot args))
      (= command "/topic") (info current-topic)
      (= command "/context") (info context)
      ;;
      (.startswith line "/") (error f"Unknown command **{command}**.")
      ;;
      ;; otherwise, normal chat
      :else (do (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
                  (let [reply-msg (reply bot (inject system-prompt chat-history))]
                    (.append chat-history reply-msg)
                    (print-message reply-msg margin)))))
    ;;
    chat-history))
