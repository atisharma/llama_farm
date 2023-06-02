"
Functions that return text from queries.
"

;; TODO: a lot of this could be abstracted by macros.

(require hyrule.argmove [-> ->> as->])

(import itertools [repeat])

(import langchain.chains [RetrievalQA
                          VectorDBQA
                          ConversationalRetrievalChain
                          AnalyzeDocumentChain])
(import langchain.chains.summarize [load-summarize-chain])

(import langchain.utilities [WikipediaAPIWrapper ArxivAPIWrapper])
(import langchain.tools [DuckDuckGoSearchRun])
(import langchain.retrievers [WikipediaRetriever ArxivRetriever])
(import langchain.schema [BaseRetriever])

(import .texts [url->text youtube->text])
(import .documents [url->docs youtube->docs file->docs])


;;; -----------------------------------------------------------------------------
;;; Query functions as Retrievers
;;; -----------------------------------------------------------------------------

(defclass URLRetriever [BaseRetriever]
  "Converts a url to docs via clean markdown."
  (defn get-relevant-documents [url]
    (url->docs url)))
    
(defclass YoutubeRetriever [BaseRetriever]
  "Converts a Youtube transcript to docs via clean markdown."
  (defn get-relevant-documents [youtube-id]
    (youtube->docs youtube-id)))

(defclass FileRetriever [BaseRetriever]
  "Converts a file to docs."
  (defn get-relevant-documents [fname]
    (file->docs fname)))

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
;;; Chat completion models: ..., chat-model, query, chat, retriever -> {query result}
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

(defn chat-arxiv [#* args
                  [chain-type "stuff"]
                  #** kwargs]
  "Function that converses over an arXiv search and chat history."
  (chat-retriever #* args
                  :retriever (ArxivRetriever)
                  :chain-type chain-type
                  #** kwargs))

;; FIXME: YoutubeRetriever needs to be passed the specific youtube ID not the whole query
(defn chat-youtube [#* args
                    [chain-type "stuff"]
                    #** kwargs]
  "Function that converses over a Youtube transcript and chat history."
  (chat-retriever #* args
                  :retriever (YoutubeRetriever)
                  :chain-type chain-type))

;; FIXME: URLRetriever needs to be passed the specific URL not the whole query
(defn chat-url [#* args
                [chain-type "stuff"]
                #** kwargs]
  "Function that converses over a webpage and chat history."
  (chat-retriever #* args
                  :retriever (URLRetriever)
                  :chain-type chain-type))

;; FIXME: FileRetriever needs to be passed the specific filename not the whole query
(defn chat-file [#* args
                 [chain-type "stuff"]
                 #** kwargs]
  "Function that converses over a file and chat history."
  (chat-retriever #* args
                  :retriever (FileRetriever)
                  :chain-type chain-type))

;;; -----------------------------------------------------------------------------
;;; Summary / query functions : model, query -> text
;;; -----------------------------------------------------------------------------

(defn summarize [model text]
  "Summarize a long text (as text)."
  (let [summary-chain (load-summarize-chain model
                                            :chain_type "map_reduce")
        summarize-document-chain (AnalyzeDocumentChain :combine-docs-chain summary-chain)]
    (.run summarize-document-chain text)))

(defn summarize-youtube [model youtube-id]
  "Summarize a youtube video transcript (as text)."
  (->> youtube-id
       (youtube->text)
       (summarize model)))  

(defn summarize-url [model url]
  "Summarize a webpage (as text)."
  (->> url
       (url->text)
       (summarize model)))  
