"A vector db store api.
 
The `store` api uses langchain's ChromaDB or FAISS adapter to provide
functions for the ingestion, loading, and retrieval of documents. It
uses HuggingFace embeddings to represent documents, a
RecursiveCharacterTextsplitter to split text into chunks. It supports
ingesting both text and pdf documents, as well as various search types
such as MMR and similarity.

To use the api, you must set up specify the embeddings model name,
tokenizer and chunk sizes in the config file under the [db]
section. The `db` function creates a vector store at the given
directory.

Then, you can call the functions to ingest and load documents, as well
as perform retrieval searches. The ingest function takes a list of
document objects and adds them to the vector store. The load-text and
load-pdf functions are used to create a list of document objects from
text and pdf files, respectively. The load-dir function operates
recursively over a directory's contents.

Finally, the similarity and relevance functions can be used to perform
similarity and MMR searches, respectively, using a query string and an
optional k value to specify the number of results.

"

;;; TODO: bash / inode files etc to detect changes in fs and ingest new files


(require hyrule.argmove [-> ->>])

(import os)

(import langchain.embeddings [HuggingFaceEmbeddings])
(import langchain.vectorstores [Chroma FAISS])
(import langchain.schema [Document])
(import langchain.docstore.in_memory [InMemoryDocstore])

;; do some nicer logging here
(import rich [print])

(import .utils [config hash-id])
(import .documents [load url])


(setv embedding (HuggingFaceEmbeddings :model-name (config "storage" "embedding")))

;;; -----------------------------------------------------------------------------
;;; functions to modify/create vectorstores : ? -> ?
;;; -----------------------------------------------------------------------------

(defn chroma [db-name]
  "Persistent Chroma vectorstore instance.
   Chroma langchain integration has a bug that prevents reliable loading."
  (import chromadb.config [Settings :as chroma-settings])
  (import chromadb.errors [DuplicateIDError IDAlreadyExistsError])
  (let [settings (chroma-settings :anonymized-telemetry False
                                  :persist-directory db-name
                                  :chroma-db-impl "duckdb+parquet")
        db (Chroma :embedding-function embedding
                   :persist-directory db-name
                   :collection-name db-name
                   :client-settings settings)]
    (setv db.path db-name
          db.kind "chroma")
    db))

(defn faiss [db-path]
  "Persistent FAISS vectorstore instance.
   Faiss is more powerful search than Chroma, but is more complicated.
   I don't know how to delete dupes in Faiss because langchain uses
   random ID for insertion."
  ;; for special operations on an underlying faiss store, see
  ;; https://github.com/facebookresearch/faiss/wiki/Special-operations-on-indexes
  (import faiss [IndexFlatL2])
  (let [db (if (os.path.isdir db-path)
               (FAISS.load-local db-path embedding)
               (FAISS :embedding-function embedding.embed-query
                      :index (IndexFlatL2 (len (embedding.embed-query "get the embedding dimension")))
                      :docstore (InMemoryDocstore {})
                      :index-to-docstore-id {}))]
    (setv db.path db-path
          db.kind "faiss")
    db))

(defn ingest-docs [db docs]
  "Ingest a Document list into the vector db.
   The id is a hash of the Document, since it must be unique.
   This means it's impossible to replace a document with this hashing scheme."
  (let [ids (gfor d docs (hash-id (str d)))
        docs-map (dict (zip ids docs))
        uids (.keys docs-map)
        udocs (.values docs-map)]
    ; would be cuter to use a multimethod
    ; but let's not over-engineer this yet
    (match db.kind
           "chroma" (do
                      (print "[blue]Deleting documents to be replaced.[/blue]")
                      (db._collection.delete uids)
                      (db.index.remove-ids)
                      (print "[blue]Adding documents.[/blue]")
                      (db.add_documents udocs :ids uids)
                      (print f"[blue]Saving vector store to {db.path}/.[/blue]")
                      (db.persist))
           "faiss" (do
                     ; only insert docs that aren't already in the db
                     (let [new-ids (list (.difference (set uids)
                                                      (set (.values db.index-to-docstore-id))))
                           new-docs (lfor i new-ids (get docs-map i))]
                       (print "[blue]Adding new documents.[/blue]")
                       (db.add_documents new-docs :ids new-ids)
                       (print f"[blue]Saving vector store to {db.path}/.[/blue]")
                       (db.save-local db.path))))))

(defn ingest-files [db fname [verbose True]]
  "Load files or directories and ingest them."
  (ingest-docs db (load fname :verbose verbose)))

(defn ingest-urls [db urls [verbose True]]
  "Load url(s) and ingest them."
  (ingest-docs db (url urls :verbose verbose)))

;;; -----------------------------------------------------------------------------
;;; search : vectorstore, query -> Documents
;;; -----------------------------------------------------------------------------

(defn similarity [db query [k 4]]
  "Similarity search."
  (db.similarity-search query :k k))

(defn mmr [db query [k 4]]
  "Maximum marginal relevance (MMR) search."
  (let [retriever (db.as-retriever :search-type "mmr"
                                   :search-kwargs {"k" k})]
    (retriever.get-relevant-documents query)))
