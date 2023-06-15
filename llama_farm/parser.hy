"
Parse user input and dispatch the resulting operation,
either internally or to a chatbot / langchain.
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import os)
(import shlex)
(import logging)

(import llama-farm [store chat])
(import .state [chat-store knowledge-store])
(import .utils [params config bots slurp is-url msg system user inject])
(import .texts [now->text url->text arxiv->text youtube->text wikipedia->text])
(import .interface [banner
                    bot-color
                    clear
                    clear-status-line
                    console
                    error
                    get-margin
                    info
                    print-chat-history
                    print-docs
                    print-message
                    print-sources
                    set-width
                    spinner-context
                    status-line
                    tabulate
                    toggle-markdown])

(import requests.exceptions [MissingSchema ConnectionError])
(import youtube-transcript-api._errors [TranscriptsDisabled])


;; TODO: status-line: history (tokens) | model | current-topic | current tool
;; TODO: remove global state for current topic and context.
;; TODO: move all spinners to this top level -- a function decorator would be nice, that didn't clash with existing indicators

(setv bot (config "bots" "default")
      current-topic ""
      context ""
      knowledge "")

;;; -----------------------------------------------------------------------------
;;; functions for internal use
;;; -----------------------------------------------------------------------------

(defn help-str []
  "Return the help string."
  (slurp (or (+ (os.path.dirname __file__) "/help.md")
             "llama_farm/help.md")))

(defn _ingest [#* args]
  "A convenience wrapper."
  (try
    (for [f args]
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
;;; The parser: message, list[message] -> list[message]
;;; -----------------------------------------------------------------------------

(defn parse [user-message chat-history]
  "Take as input user-message: {role: user, content: line}, the chat history: [list messages], and bot: (system prompt string).
   Do the action resulting from `line`, and return the updated chat history."
  (global bot context knowledge current-topic)
  (clear-status-line)
  (let [chain-type (or (config "chain-type") "stuff")
        bot-prompt (:system_prompt (params bot) "")
        bot-name (.capitalize bot)
        time-prompt f"Today's date and time is {(now->text)}."
        system-prompt f"{time-prompt}\n{bot-prompt}\nYou are talking to the user called {(.capitalize (:bot user-message))}.\n{context}\n{knowledge}"
        line (:content user-message)
        margin (get-margin chat-history)
        [_command _ args] (.partition line " ")
        command (.lower _command)]
    (let [_chat-dict (chat.truncate bot
                                    system-prompt
                                    :chat-history chat-history
                                    :current-topic current-topic
                                    :context context
                                    :knowledge knowledge)]
      (setv chat-history (:chat-history _chat-dict)
            context (:context _chat-dict)
            knowledge (:knowledge _chat-dict)
            current-topic (:current-topic _chat-dict)))
    (cond
      ;;
      ;; commands that give a reply
      (= command "/ask") (chat.extend chat-history
                                      user-message
                                      (chat.over-db bot
                                                    user-message
                                                    args
                                                    (inject system-prompt chat-history)
                                                    :db knowledge-store))
      (= command "/arxiv") (chat.extend chat-history
                                        user-message
                                        (chat.over-arxiv bot
                                                         user-message
                                                         args
                                                         (inject system-prompt chat-history)))
      (= command "/wikipedia") (chat.extend chat-history
                                            user-message
                                            (chat.over-wikipedia bot
                                                                 user-message
                                                                 args
                                                                 (inject system-prompt chat-history)))
      (= command "/file") (chat.extend chat-history
                                       user-message
                                       (chat.over-file bot
                                                       user-message
                                                       args
                                                       (inject system-prompt chat-history)))
      (= command "/url") (chat.extend chat-history
                                      user-message
                                      (chat.over-url bot
                                                     user-message
                                                     args
                                                     (inject system-prompt chat-history)))
      (= command "/youtube") (chat.extend chat-history
                                          user-message
                                          (chat.over-youtube bot
                                                             user-message
                                                             args
                                                             (inject system-prompt chat-history)))
      ;;
      ;; summarization
      (= command "/summ-file") (try
                                 (chat.extend chat-history
                                              user-message
                                              (chat.over-summarize-file bot
                                                                        user-message
                                                                        args
                                                                       (inject system-prompt chat-history)))
                                 (except [e [MissingSchema ConnectionError]]
                                   (error f"I can't get anything from [{args}]({args})")))
      (= command "/summ-url") (try
                                (chat.extend chat-history
                                             user-message
                                             (chat.over-summarize-url bot
                                                                      user-message
                                                                      args
                                                                      (inject system-prompt chat-history)))
                                (except [e [MissingSchema ConnectionError]]
                                  (error f"I can't get anything from [{args}]({args})")))
      (= command "/summ-youtube") (try
                                    (chat.extend chat-history
                                                 user-message
                                                 (chat.over-summarize-youtube bot
                                                                              user-message
                                                                              args
                                                                              (inject system-prompt chat-history)))
                                    (except [TranscriptsDisabled]
                                      (error f"I can't find a transcript for [{args}](https://www.youtube.com/watch/?v={args})")))
      ;;
      ;; printing / debugging commands
      (= command "/system") (info system-prompt)
      (= command "/print-url") (try
                                 (info (url->text args))
                                 (except [e [MissingSchema ConnectionError]]
                                   (error f"I can't get anything from [{args}]({args})")))
      (= command "/print-youtube") (try
                                     (info (youtube->text args))
                                     (except [TranscriptsDisabled]
                                       (error f"I can't find a transcript for [{args}](https://www.youtube.com/watch/?v={args})")))
      ;;
      (= command "/print-arxiv") (info (arxiv->text args))
      (= command "/print-wikipedia") (info (wikipedia->text args))
      ;;
      ;; interface commands
      (= command "/clear") (clear)
      (= command "/banner") (do (clear) (banner) (console.rule))
      (= command "/width") (set-width line)
      (= command "/markdown") (toggle-markdown)
      (= command "/reset!") (do (info "Conversation discarded.")
                                (setv chat-history []
                                      current-topic ""
                                      context ""
                                      knowledge ""))
      (= command "/undo") (setv chat-history (cut chat-history 0 -2))
      (in command ["/h" "/help"]) (info (help-str))
      ;;
      ;; bot / chat commands
      (= command "/bot") (do (set-bot args) (setv bot-name (.capitalize bot)))
      (= command "/bots") (_list-bots)
      (in command ["/history" "/hist"]) (print-chat-history chat-history
                                                            :tokens (chat.token-count (inject system-prompt chat-history)))
      ;;
      ;; chat memory management
      (= command "/topic") (if args
                               (setv current-topic args)
                               (with [c (spinner-context f"{bot-name} is summarizing...")]
                                 (setv current-topic (chat.topic bot chat-history))
                                 (info current-topic)))
      (= command "/context") (when current-topic
                               (setv context (chat.recall chat-store bot current-topic)
                                     knowledge (chat.recall knowledge-store bot current-topic))
                               (info context)
                               (info knowledge))
      ;;
      ;; vectorstore commands
      (= command "/ingest") (_ingest #* (shlex.split args))
      (= command "/sources") (print-sources (store.mmr knowledge-store args))
      (= command "/similarity") (print-docs (store.similarity knowledge-store args))
      (= command "/recall") (info (chat.recall chat-store bot (or args current-topic)))
      (= command "/know") (info (chat.recall knowledge-store bot (or args current-topic)))
      ;;
      (.startswith line "/") (error f"Unknown command **{command}**.")
      ;;
      ;; otherwise, just chat
      :else (let [reply-message (chat.reply bot chat-history user-message system-prompt)]
              (chat.extend chat-history user-message reply-message)
              (print-message reply-message margin)))
      ;;
    (status-line f"[{(bot-color bot)}]{bot-name}[default] | [green]{(chat.token-count (inject system-prompt chat-history))} tkns | {current-topic}")
    chat-history))
