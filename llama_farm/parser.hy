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
(import .utils [config is-url msg system])
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
;; TODO: status-line: history (tokens) | model | current-topic | curent tool

(setv bot (get (bots) 0))

(setv knowledge-store (store.faiss (os.path.join (config "storage" "path")
                                                 "knowledge.faiss")))

; TODO: chat over chat history
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

- **/remember**                     Save the conversation to an bot's long-term memory
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
;;; Enquiry functions: query ... -> message pair
;;; -----------------------------------------------------------------------------

;; TODO: abstract out boilerplate here

(defn enquire-db [bot user-message args chat-history * chain-type]
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          reply (ask.chat-db knowledge-store
                             (model bot)
                             args
                             chat-history
                             :chain-type chain-type
                             :sources True
                             :search-kwargs {"k" (or (config "storage" "sources") 6)})]
      (print-sources (:source-documents reply))
      (let [reply-msg (msg "assistant" f"{(:answer reply)}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"Knowledge query: {args}"} reply-msg]))))

(defn enquire-wikipedia [bot user-message args chat-history * chain-type]
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          reply (ask.chat-wikipedia (model bot)
                                    args
                                    chat-history
                                    :chain-type chain-type
                                    :sources True)]
      (let [reply-msg (msg "assistant" f"{(:answer reply)}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"Wikipedia query: {args}"} reply-msg]))))

(defn enquire-arxiv [bot user-message args chat-history * chain-type]
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          reply (ask.chat-arxiv (model bot)
                                args
                                chat-history
                                :chain-type chain-type
                                :sources True)]
                                ;:load-max-docs (config "storage" "arxiv_max_docs"))]
      (let [reply-msg (msg "assistant" f"{(:answer reply)}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"ArXiv query: {args}"} reply-msg]))))

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
  (global bot)
  (let [chain-type (or (config "repl" "chain-type") "stuff")
        system-prompt (:system_prompt (params bot))
        line (:content user-message)
        margin (get-margin chat-history)
        [_command _ args] (.partition line " ")
        command (.lower _command)]
    (unless (.startswith line "/")
      (.append chat-history user-message))
    (cond
      ;; commands that give a reply
      ;;
      ;; move this to a function, and call with different chain-types, k, search type.
      (= command "/ask") (.extend chat-history (enquire-db bot user-message args chat-history
                                                           :chain-type chain-type))
      (= command "/wikipedia") (.extend chat-history (enquire-wikipedia bot user-message args chat-history
                                                                        :chain-type chain-type))
      (= command "/arxiv") (.extend chat-history (enquire-arxiv
                                                   bot
                                                   user-message
                                                   args
                                                   chat-history
                                                   :chain-type chain-type))
      (= command "/url") (try
                           (.extend chat-history (enquire-summarize-url bot
                                                                        user-message
                                                                        args
                                                                        chat-history))
                           (except [e [MissingSchema ConnectionError]]
                             (error f"I can't get anything from [{args}]({args})")))
      ;; TODO: pass in youtube-id
      (= command "/youtube") (try
                               (.extend chat-history
                                        (enquire-summarize-youtube bot
                                                                   user-message
                                                                   args
                                                                   chat-history))
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
      (= command "/help") (info help-str)
      (= command "/h") (info help-str)
      (= command "/version") (info (version "llama_farm"))
      ;;
      ;; bot / chat commands
      (= command "/bot") (set-bot args)
      (= command "/bots") (_list-bots)
      (= command "/personalities") (_list-bots)
      (= command "/history") (print-chat-history chat-history)
      ;;
      ;; vectorstore commands
      (= command "/ingest") (_ingest knowledge-store args)
      ;;
      (.startswith line "/") (error f"Unknown command **{command}**.")
      ;;
      ;; otherwise, normal chat
      :else (do (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
                  (let [reply-msg (reply bot chat-history system-prompt)]
                    (.append chat-history reply-msg)
                    (print-message reply-msg margin)))))
    ;;
    chat-history))
