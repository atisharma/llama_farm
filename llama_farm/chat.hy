"
Functions that return messages or are associated with chat management.
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import shlex)

(import llama-farm [store generate summaries])
(import .state [chat-store knowledge-store])
(import .documents [tokenizer token-count chat->docs])
(import .utils [config params
                file-append slurp
                format-docs format-chat-history
                prepend append
                msg user system])
(import .texts [now->text youtube-meta->text wikipedia->text url->text youtube->text])
(import .interface [get-margin
                    print-message
                    print-sources
                    bot-color
                    spinner-context
                    error])


;;; -----------------------------------------------------------------------------
;;; chat management
;;; -----------------------------------------------------------------------------

(defn truncate [bot system-prompt * chat-history current-topic context knowledge]
  "Shorten the chat history if it gets too long, in which case:
   - split it and store the first part in the chat store.
   - set a new context.
   Return the (new or old) chat history, context, topic."
  (let [context-length (:context-length (params bot) 2000)
        max-tokens (:max-tokens (params bot) 50)
        truncation-length (- context-length max-tokens)
        ; need enough space to provide whole chat + system msg + new text
        token-length (+ max-tokens (token-count (prepend (system system-prompt) chat-history)))
        ;; assume chat length is multiple of 2 (else we lose order of response)
        cut-length (* 2 (// (len chat-history) 4))]
    (if (> token-length truncation-length)
      (let [pre (cut chat-history cut-length)
            post (cut chat-history cut-length None)
            new-topic (summaries.chat-topic bot post)]
        (commit-chat bot pre)
        {"chat_history" post
         "current_topic" new-topic
         "context" (recall chat-store bot new-topic :chatdb True)
         "knowledge" (recall knowledge-store bot new-topic)})
      {"chat_history" chat-history
       "current_topic" (if (>= (len chat-history) 4)
                           (summaries.chat-topic bot chat-history)
                           current-topic)
       "context" context
       "knowledge" knowledge})))

(defn commit-chat [bot chat]
  "Save a chat history fragment to the chat store."
  (let [chat-topic (summaries.chat-topic bot chat)
        docs (chat->docs chat chat-topic)]
    (store.ingest-docs chat-store docs)))

(defn recall [db bot topic [blockquote False] [chatdb False]] ; -> text
  "Summarise a topic from the cat memory store.
   Return a summary text which may then be used for injection in the system message."
  (with [c (spinner-context f"{(.capitalize bot)} is recalling...")]
    (let [username (or (.lower (config "user")) "user")
          query f"The query is: {topic}"
          k (or (config "storage" "sources") 6)
          search-str (if chatdb f"{topic} {bot} {username}" topic)
          docs (store.similarity db search-str :k k)
          chat-str (format-docs docs)
          quoted-str (+ "> " (.replace chat-str "\n" "\n> "))]
      (if blockquote
          (.join "\n\n"
                 [(summaries.extract bot chat-str query :max-token-length 250)
                  quoted-str])
          (summaries.extract bot chat-str query :max-token-length 250)))))

(defn process [chat-history #* msgs]
  "Simply append the new messages to the chat history, log the change, and return it."
  (for [msg msgs]
    (.append chat-history msg)
    (file-append msg (config "chatlog"))
    (when (= "assistant" (:role msg))
      (speak msg)))
  chat-history)

(defn speak [msg]
  "Speak if and how configured to do so."
  (let [tts-engine (config "speech")
        bot (:bot msg)
        text (:content msg)]
    (when text
      (with [c (spinner-context f"{(.capitalize bot)} is speaking..." :style f"italic {(bot-color bot)}")]
        (cond (= tts-engine "bark") (do
                                      (import .bark [speak])
                                      (speak text
                                             :voice (:bark-voice (params bot) "v2/en_speaker_0")))
              (= tts-engine "balacoon") (do
                                          (import .balacoon [speak])
                                          (speak text
                                                 :model (config "balacoon_model")
                                                 :speaker (:balacoon-speaker (params bot)))))))))

;; TODO: call tools if appropriate
(defn reply [bot chat-history user-message system-prompt] ; -> msg
  "Simply reply to the chat with a message."
  (with [c (spinner-context f"{(.capitalize bot)} is thinking..." :style f"italic {(bot-color bot)}")]
    (let [messages (->> chat-history (prepend (system system-prompt)) (append user-message))]
      (generate.chat bot messages))))

;; TODO: call tools if appropriate
(defn reply-over-text [bot chat-history user-message text] ; -> msg
  "Reply to the chat and provided context with a message. Text should already be summarized."
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [output (generate.text&msgs->reply bot chat-history text (:content user-message))]
      (msg "assistant" output bot))))

;;; -----------------------------------------------------------------------------
;;; Chat over text functions: query ... -> message pair
;;; -----------------------------------------------------------------------------

;; TODO: abstract out boilerplate here

(defn over-text [bot user-message args chat-history * text] ; -> print, msg
  "Chat over some text. Print the reply message and return it."
  (let [margin (get-margin chat-history)
        context-length (:context-length (params bot) 2000)
        max-tokens (:max-tokens (params bot) 750)
        truncation-length (- context-length max-tokens)
        spare-tokens (- truncation-length
                        max-tokens
                        (token-count chat-history))
        query (:content user-message)
        short-text (with [c (spinner-context f"{(.capitalize bot)} is extracting info...")]
                     (summaries.extract bot text query :max-token-length spare-tokens))
        reply-msg (reply-over-text bot chat-history user-message short-text)]
    (print-message reply-msg margin)
    reply-msg))

(defn over-docs [bot user-message args chat-history * docs [sources False]]
  "Chat over a set of documents."
  (when sources (print-sources docs))
  (let [text (format-docs docs)]
    (over-text bot user-message args chat-history :text text)))

(defn over-db [bot user-message args chat-history * db [sources False]]
  (let [k (or (config "storage" "sources") 6)
        docs (store.similarity db args :k k)]
    (over-docs bot user-message args chat-history :docs docs :sources sources)))

(defn over-wikipedia [bot user-message args chat-history]
  (let [[topic _ query] (.partition args " ")
        text (wikipedia->text topic)]
    (over-text bot user-message args chat-history :text text)))

(defn over-file [bot user-message args chat-history]
  (let [[fname _ query] (.partition args " ")
        text (slurp fname)]
    (if text
      (over-text bot user-message query chat-history :text text)
      (error f"I can't find {fname}, or it's empty."))))

(defn over-arxiv [bot user-message args chat-history]
  (let [[topic _ query] (.partition args " ")
        text (arxiv->text topic)]
    (over-text bot user-message args chat-history :text text)))

(defn over-url [bot user-message args chat-history]
  "Chat over a URL. The first word in args must be the URL."
  (let [[url _ query] (.partition args " ")
        text (url->text url)]
    (over-text bot user-message args chat-history :text text)))
  
(defn over-youtube [bot user-message args chat-history]
  "Chat over a youtube transcript. The first word in args must be the youtube id."
  (let [[youtube-id _ query] (.partition args " ")
        text (youtube->text youtube-id)]
    (over-text bot user-message args chat-history :text text)))
  
(defn over-summarize-file [bot user-message fname chat-history]
  "Summarize a URL."
  (with [c (spinner-context f"{(.capitalize bot)} is summarizing...")]
    (let [margin (get-margin chat-history)
          summary (summaries.summarize-file bot fname)]
      (let [reply-msg (msg "assistant" f"{summary}" bot)]
        (print-message reply-msg margin)
        reply-msg))))

(defn over-summarize-url [bot user-message url chat-history]
  "Summarize a URL."
  (with [c (spinner-context f"{(.capitalize bot)} is summarizing...")]
    (let [margin (get-margin chat-history)
          summary (summaries.summarize-url bot url)
          reply-msg (msg "assistant" f"{summary}" bot)]
      (print-message reply-msg margin)
      reply-msg)))

(defn over-summarize-youtube [bot user-message youtube-id chat-history]
  "Summarize a Youtube video (transcript)."
  (with [c (spinner-context f"{(.capitalize bot)} is summarizing...")]
    (let [margin (get-margin chat-history)
          summary (summaries.summarize-youtube bot youtube-id)
          reply-msg (msg "assistant" summary bot)]
      (print-message reply-msg margin)
      reply-msg)))
