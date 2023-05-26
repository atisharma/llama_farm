"
Functions that return text from queries.
"

(import itertools [repeat])
(import datetime [datetime])

(import langchain.chains [RetrievalQA VectorDBQA ConversationalRetrievalChain])
(import langchain.utilities [WikipediaAPIWrapper ArxivAPIWrapper])
(import langchain.tools [DuckDuckGoSearchRun])
(import langchain.retrievers [WikipediaRetriever ArxivRetriever])


;;; -----------------------------------------------------------------------------
;;; LLM query functions : db | retriever, llm, query -> text
;;; -----------------------------------------------------------------------------

;;; -----------------------------------------------------------------------------
;;; Text completion models: ..., llm, query -> {query result}
;;; -----------------------------------------------------------------------------

(defn retriever [retriever llm query
                 [chain-type "stuff"]
                 [sources False]]
  "Q&A function that takes a generic retriever and returns a dict `{query result}`."
  ((RetrievalQA.from-chain-type :llm llm
                                :return-source-documents sources
                                :retriever retriever
                                :chain-type chain-type)
   query))

(defn db [db llm query
          [chain-type "stuff"]
          [sources False]
          #** db-retriever-args]
  "Q&A function that takes a vectorstore and query to return a dict `{query result}`."
  (retriever (db.as-retriever #** db-retriever-args)
             llm
             query
             :chain-type chain-type
             :sources sources))

(defn wikipedia [llm query #** kwargs]
  "Q&A function that looks up relevant information on Wikipedia."
  (retriever (WikipediaRetriever)
             llm
             query
             #** kwargs))

;;; -----------------------------------------------------------------------------
;;; Chat completion models: ..., chat-model, query -> {query result}
;;; -----------------------------------------------------------------------------

(defn chat-retriever [chat-llm query chat-history
                      [retriever retriever] 
                      [chain-type "stuff"]
                      [sources False]]
  "Function that converses over a retriever query and chat history."
  (let [queries (lfor m chat-history :if (= (:role m) "user") (:content m))
        answers (lfor m chat-history :if (in (:role m) ["assistant" "bot"]) (:content m))
        ;; assumes alternating user and bot messages
        qa-chat-history (list (zip queries answers))]
    ((ConversationalRetrievalChain.from-llm :llm chat-llm
                                            :return-source-documents sources
                                            :chain-type chain-type
                                            :retriever retriever)
     {"question" query
      "chat_history" qa-chat-history})))

(defn chat-db [db
               #* args
               [chain-type "stuff"]
               [sources False]
               #** kwargs]
  "Function that converses over a vectorstore query and chat history."
  (chat-retriever #* args
                  :retriever (db.as-retriever #** kwargs)
                  :chain-type chain-type
                  :sources sources))

(defn chat-wikipedia [#* args
                      [chain-type "stuff"]
                      #** kwargs]
  "Function that converses over a wikipedia query and chat history."
  (chat-retriever #* args
                  :retriever (WikipediaRetriever)
                  :chain-type chain-type))

;;; -----------------------------------------------------------------------------
;;; Other query functions : query | ? -> text
;;; -----------------------------------------------------------------------------

(defn wikipedia-summary [topic]
  "Get the Wikipedia summary on a topic (as text)."
  (.run (WikipediaAPIWrapper) topic))

(defn ddg [topic]
  "Get the DuckDuckGo summary on a topic (as text)."
  (.run (DuckDuckGoSearchRun) topic))

(defn arxiv [topic]
  "Get the arxiv summary on a topic (as text)."
  (.run (ArxivAPIWrapper) topic))

(defn today [[fmt "%Y-%m-%d"]]
  "Today's date."
  (.strftime (datetime.today) fmt))

(defn now []
  "Current timestamp in isoformat."
  (.isoformat (datetime.today)))

(defn tldr [topic]
  "TL;DR man page alternative for a topic.")
