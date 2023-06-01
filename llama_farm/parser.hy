"
Parse user input and dispatch the resulting operation,
either internally or to a chatbot / langchain.
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import os)
(import shlex)
(import logging)

(import llama-farm [ask store chat])
(import .state [chat-store knowledge-store])
(import .models [bots params reply])
(import .utils [config slurp is-url msg system user inject file-append])
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

(setv bot (config "bots" "default")
      current-topic "No topic is set yet."
      context "")

;;; -----------------------------------------------------------------------------
;;; functions for internal use
;;; -----------------------------------------------------------------------------

(defn help-str []
  "Return the help string."
  (slurp (or (+ (os.path.dirname __file__) "/help.md")
             "llama_farm/help.md")))

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
        system-prompt f"{time-prompt}\n{bot-prompt}\nYou are talking to the user called {(.capitalize (:bot user-message))}.\n{context}"
        line (:content user-message)
        margin (get-margin chat-history)
        [_command _ args] (.partition line " ")
        command (.lower _command)]
    (unless (.startswith line "/")
      (let [_chat-dict (chat.truncate bot
                                      system-prompt
                                      :chat-history chat-history
                                      :current-topic current-topic
                                      :context context)]
        (setv chat-history (:chat-history _chat-dict)
              context (:context _chat-dict)
              current-topic (:current-topic _chat-dict)))
      ; TODO: consolidate the places where the chat history is added to
      (.append chat-history user-message)
      (file-append user-message (config "chatlog")))
    (cond
      ;; commands that give a reply
      ;;
      ;; move this to a function, and call with different chain-types, k, search type.
      (= command "/ask") (.extend chat-history
                                  (chat.enquire-db
                                    bot
                                    user-message
                                    args
                                    (inject system-prompt chat-history)
                                    :chain-type chain-type))
      (= command "/wikipedia") (.extend chat-history
                                        (chat.enquire-wikipedia
                                          bot
                                          user-message
                                          args
                                          (inject system-prompt chat-history)
                                          :chain-type chain-type))
      (= command "/arxiv") (.extend chat-history
                                    (chat.enquire-arxiv
                                      bot
                                      user-message
                                      args
                                      (inject system-prompt chat-history)
                                      :chain-type chain-type))
      (= command "/url") (try
                           (.extend chat-history (chat.enquire-summarize-url bot
                                                                        user-message
                                                                        args
                                                                        (inject system-prompt chat-history)))
                           (except [e [MissingSchema ConnectionError]]
                             (error f"I can't get anything from [{args}]({args})")))
      (= command "/youtube") (try
                               (.extend chat-history
                                        (chat.enquire-summarize-youtube bot
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
      (in command ["/h" "/help"]) (info (help-str))
      (= command "/version") (info (version "llama_farm"))
      ;;
      ;; bot / chat commands
      (= command "/bot") (do (set-bot args) (setv bot-name (.capitalize bot)))
      (= command "/bots") (_list-bots)
      (in command ["/history" "/hist"]) (print-chat-history chat-history
                                                            :tokens (chat.token-count (inject system-prompt chat-history)))
      ;;
      ;; vectorstore commands
      (= command "/ingest") (_ingest knowledge-store args)
      (= command "/sources") (info (format-sources (store.mmr knowledge-store args)))
      (= command "/recall") (info (chat.recall chat-store bot args))
      (= command "/know") (info (chat.recall knowledge-store bot args))
      (= command "/topic") (if args
                               (setv current-topic args)
                               (with [c (spinner-context f"{bot-name} is summarizing...")]
                                 (setv current-topic (chat.topic bot chat-history))
                                 (info current-topic)))
      (= command "/context") (do (setv context (chat.recall chat-store bot current-topic))
                                 (info context))
      (= command "/system") (info system-prompt)
      ;;
      (.startswith line "/") (error f"Unknown command **{command}**.")
      ;;
      ;; otherwise, normal chat
      :else (with [c (spinner-context f"{bot-name} is thinking...")]
              (let [reply-msg (reply bot (inject system-prompt chat-history))]
                (.append chat-history reply-msg)
                (file-append reply-msg (config "chatlog"))
                (print-message reply-msg margin))))
    ;;
    (status-line f"[{(bot-color bot)}]{bot-name}[default] | [green]{(chat.token-count (inject system-prompt chat-history))} tkns | {current-topic}")
    chat-history))
