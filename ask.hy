"
Functions that return text.
"

(import datetime [datetime])

(import langchain.chains [RetrievalQA VectorDBQA ConversationalRetrievalChain])
(import langchain.utilities [WikipediaAPIWrapper ArxivAPIWrapper])
(import langchain.tools [DuckDuckGoSearchRun])


;;; -----------------------------------------------------------------------------
;;; LLM query functions : db, llm, query -> text
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
          #** retriever-args]
  "Q&A function that takes a vectorstore and query to return a dict `{query result}`."
  (retriever (db.as-retriever #** retriever-args)
             llm
             query))

(defn converse [db llm query
                [chain-type "stuff"]
                [sources False]
                #** retriever-args]
  "Function that converses over a query."
  ; uses chat model??
  ((ConversationalRetrievalChain.from-llm :llm llm
                                          :return-source-documents sources
                                          :chain-type chain-type
                                          :retriever (db.as-retriever #** retriever-args))
   query))

;;; -----------------------------------------------------------------------------
;;; Other query functions : query | ? -> text
;;; -----------------------------------------------------------------------------

(defn wikipedia [topic]
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
