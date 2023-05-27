"
Functions that produce lists of Document objects.
"

(require hyrule.argmove [-> ->>])
(require hyrule.control [unless])

(import os)
(import magic)
(import logging)

(import functools [partial])
(import itertools [chain repeat])
(import multiprocessing [Pool cpu-count])

; consider moving into the parallel loop after the fork
; but transformers is imported by langchain
(import transformers [LlamaTokenizerFast])

(import langchain.document-loaders [TextLoader
                                    UnstructuredFileLoader
                                    PyMuPDFLoader])
(import langchain.text-splitter [RecursiveCharacterTextSplitter
                                 MarkdownTextSplitter])
(import langchain.utilities [WikipediaAPIWrapper])
(import langchain.schema [Document])

(import .utils [config])
(import .interface [track spinner-context])
(import .texts [youtube->text url->text])


(setv ignored-extensions ["log" "dat" "aux" "icon" "tikz"
                          "tmp" "temp" "bkp" "dropbox"
                          "mp4" "mkv" "mov" "avi" "wmv" "flv" "webm" "mpeg" "mpg" ; movies
                          "mp3" "flac" "aac" "webm" "aiff" "wav" "ogg" "wma" "m4a" ; audio
                          "md5" "sha256" "sha512"])
(setv ignored-mime-types ["inode" "image" "video" "audio"])
(setv ignored-mime-subtypes ["octet-stream"
                             "postscript"
                             "zlib"
                             "x-git" "zip" "x-rar" "gzip" "x-bzip2"
                             "x-bytecode.python"
                             "x-ole-storage"
                             "vnd.oasis.opendocument.spreadsheet"
                             "vnd.microsoft.portable-executable"])

(setv tokenizer (LlamaTokenizerFast.from-pretrained (config "storage" "tokenizer")
                                                    :add-eos-token True)
      splitter (RecursiveCharacterTextSplitter.from-huggingface-tokenizer
                 :tokenizer tokenizer
                 :chunk-size (config "storage" "chunk-size-tokens")))

;;; -----------------------------------------------------------------------------
;;; functions to load documents from files : fname, ? -> Documents
;;; -----------------------------------------------------------------------------

(defn load-unstructured [fname]
  "Create list of document objects from a file of any type, using Unstructured."
  (let [loader (UnstructuredFileLoader fname)]
    (try
      (loader.load-and-split :text-splitter splitter)
      (except [ValueError]
        [False]))))

(defn load-text [fname] 
  "Create list of document objects from a text file, using the tokenizer."
  ; FIXME: manage plain text not decoding with utf-8
  (-> fname
    (TextLoader)
    (.load-and-split :text-splitter splitter)))

(defn load-pdf [fname] 
  "Create list of document objects from a pdf file."
  (-> fname
    (PyMuPDFLoader)
    (.load-and-split :text-splitter splitter)))

(defn load-audio [fname]
  "Create list of documents from audio, via whisper transcription."
  [False])

(defn load-file [fname]
  "Intelligently (ha!) load a file as a iterable of Document objects."
  (filter None
        (let [mime (magic.from-file fname :mime True)
              [mime-type mime-subtype] (.split mime "/")
              extension (get (.split fname ".") -1)]
          (if (or (in mime-type ignored-mime-types)
                  (in mime-subtype ignored-mime-subtypes)
                  (in extension ignored-extensions)
                  (in "/.git/" fname)
                  (in "/.svn/" fname)
                  (in "/.venv/" fname)
                  (in "/__pycache__/" fname))
              (do
                (logging.error f"Ignored: {mime} {fname}")
                [False])
              (do
                (let [disp-str f"Loading {mime} \"{fname}\""]
                  (logging.info disp-str))
                (try
                  (match mime
                      "application/pdf" (load-pdf fname)
                      "text/plain" (load-text fname)
                      otherwise (load-unstructured fname))
                  (except [UnicodeDecodeError]
                    (logging.error f"Failed to decode {fname} using utf-8: ignored.")
                    [False])
                  (except [e [TypeError]]
                    (logging.error f"Failed to embed or decode {fname}: ignored.")
                    (logging.error (repr e))
                    [False])
                  (except [e [Exception]]
                    (logging.error f"Failed with unknown error {fname}: ignored.")
                    (logging.error (repr e))
                    [False])))))))

(defn __load-file-convenience [root fname]
  (try
    (load-file (os.path.join root fname))
    (except [e [Exception]]
      (logging.error f"Error: {fname}")
      (logging.error (repr e))
      [False])))

(defn __parallel-load-files [root files]
  "Internal, parallel mapping of load-file. Use load-dir instead.
   The number of worker threads is set as db.loader-threads in config.toml.
   The default is the number of cpus."
  ;;
  ;; FIXME: parallel tokenizer;
  ;; fast tokenizer parallel, disable since parallel at file level
  ;;
  ;; FIXME: This is slower than loading in serial.
  ;;
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "false")
  (let [f (partial __load-file-convenience root)
        threads (or (config "storage" "loader-threads") (cpu-count))]
    (with [p (Pool :processes threads)]
      (->> (p.imap-unordered f files)
           (chain.from-iterable)
           (filter None)
           (list)))))

(defn __serial-load-files [root files]
  "Internal mapping of load-file. Use load-dir instead."
  (let [f (partial __load-file-convenience root)]
      (->> (map f files)
           (chain.from-iterable)
           (filter None)
           (list))))

(defn load-dir [directory]
  "Create an iterable of Document objects from all files in a directory (recursive)."
  (let [file-list (with [c (spinner-context f"Listings files")]
                    (list (os.walk directory)))]
    (gfor [root dirname files] (track file-list
                                      :description "[green italic]Ingesting files"
                                      :transient True)
          document (__serial-load-files root files)
          document)))

; TODO: think about return values; maybe track lists of ignored files?

(defn load [fname]
  "Just give me an iterable of document chunks!"
  (logging.info "Listing documents.")
  (cond (os.path.isdir fname) (load-dir fname)
        (os.path.isfile fname) (load-file fname)
        :else (raise (FileNotFoundError fname))))


;;; -----------------------------------------------------------------------------
;;; functions to load documents from other sources : ? -> Documents
;;; -----------------------------------------------------------------------------

(defn wikipedia->docs [topic]
  "Get the full Wikipedia entry on a topic, as a list of Documents."
  (-> (WikipediaAPIWrapper)
    (.load topic)
    (splitter.split-documents)))

(defn url->docs [urls]
  "Create single list of document objects from a list of URLs (or single URL), via markdown."
  (if (isinstance urls str) ; single url at this point, really
      (let [splitter (MarkdownTextSplitter :chunk-size (config "storage" "chunk-size-chars"))
            markdown (-> urls
                         (url->markdown))]
        (splitter.create-documents [markdown]
                                   :metadatas [{"source" urls "url" urls}]))
      (chain.from-iterable (lfor u urls (url u)))))

(defn youtube->docs [youtube-id]
  "Load and punctuate youtube transcript as list of documents.
   Youtube 'transcripts' are just a long list of words with no punctuation
   or identification of the speaker, so we apply a punctuation filter.
   Youtube transcripts also tend to be long and rambling, so we need to
   summarize them."
  (let [text (youtube->text youtube-id)
        url f"https://www.youtube.com/watch?v={youtube-id}"
        doc (Document :page-content text
                      :metadata {"source" url "youtube-id" youtube-id})]
    (splitter.split-documents [doc])))
