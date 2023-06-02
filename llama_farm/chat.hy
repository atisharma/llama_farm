"
Functions that return messages or are associated with chat management.
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import llama-farm [ask store models])
(import .state [chat-store knowledge-store])
(import .documents [tokenizer chat->docs])
(import .utils [config slurp msg inject user])
(import .interface [get-margin
                    print-message
                    print-sources
                    spinner-context])


;;; -----------------------------------------------------------------------------
;;; chat management
;;; -----------------------------------------------------------------------------

(defn token-count [x]
  "The number of tokens, roughly, of a chat history (or anything with a meaningful __repr__)."
  (->> x
       (str)
       (tokenizer.encode)
       (len)))

(defn truncate [bot system-prompt * chat-history current-topic context]
  "Shorten the chat history if it gets too long, in which case:
   - split it in two and store the first part in the chat store.
   - set a new context.
   Return the (new or old) chat history, context, topic."
  (let [truncation-length (:truncation-length (models.params bot) 1400)
        max-tokens (:max-tokens (models.params bot) 12)
        ; need enough space to provide whole chat + system msg + new text
        token-length (+ max-tokens (token-count (inject system-prompt chat-history)))
        cut-length (// (len chat-history) 2)]
    (if (> token-length truncation-length)
      (let [pre (cut chat-history cut-length)
            post (cut chat-history cut-length None)]
        (commit-chat bot pre)
        {"chat_history" post
         "context" (recall chat-store bot current-topic)
         "current_topic" (topic bot pre)})
      {"chat_history" chat-history
       "context" context
       "current_topic" current-topic})))

(defn commit-chat [bot chat]
  "Save a chat history fragment to the chat store."
  (let [chat-topic (topic bot chat)
        docs (chat->docs chat chat-topic)]
    (store.ingest-docs chat-store docs)))

(defn recall [db bot topic [blockquote False]]
  "Summarise a topic from a memory store (usually the chat).
   Return a summary text which may then be used for injection in the system message."
  (with [c (spinner-context f"{(.capitalize bot)} is summarizing...")]
    (let [username (or (.lower (config "user")) "user")
          query f"{topic}\n{bot}:\n{username}:"
          k (or (config "storage" "sources") 6)
          docs (store.similarity db query :k k)
          chat-str (.join "\n" (lfor d docs f"{(:time d.metadata "---")}\n{d.page-content}"))
          quoted-str (+ "> " (.replace chat-str "\n" "\n> "))]
      (if blockquote
          (.join "\n\n"
                 [(ask.summarize (models.model bot) chat-str)
                  quoted-str])
          (ask.summarize (models.model bot) chat-str)))))

(defn topic [bot chat-history]
  "Determine the current topic of conversation from the chat history."
  (let [username (or (config "user") "user")
        topic-msg (user "Please summarize the conversation so far in less than ten words." username)
        topic-reply (models.reply bot (inject "Your sole purpose is to express the topic of conversation in one short sentence."
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
                             (models.model bot)
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
          reply (ask.chat-wikipedia (models.model bot)
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
          reply (ask.chat-arxiv (models.model bot)
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
          summary (ask.summarize-url (models.model bot) url)]
      (let [reply-msg (msg "assistant" f"{summary}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"Summarize the webpage {url}"} reply-msg]))))

(defn enquire-summarize-youtube [bot user-message youtube-id chat-history]
  "Summarize a Youtube video (transcript)."
  (with [c (spinner-context f"{(.capitalize bot)} is thinking...")]
    (let [margin (get-margin chat-history)
          summary (ask.summarize-youtube (models.model bot) youtube-id)]
      (let [reply-msg (msg "assistant" f"{summary}" bot)]
        (print-message reply-msg margin)
        [{#** user-message "content" f"Summarize the Youtube video [{youtube-id}](https://www.youtube.com/watch?v={youtube-id})"} reply-msg]))))
