"
Functions that produce lists of Document objects.
"

(require hyrule.argmove [-> ->>])
(require hyrule.control [unless])

(import .logger [logging])

(import os)
(import magic)

(import functools [partial])
(import itertools [chain repeat])
(import multiprocessing [Pool cpu-count])

(import transformers [LlamaTokenizerFast])

(import langchain.document-loaders [TextLoader
                                    UnstructuredFileLoader
                                    PyMuPDFLoader])
(import langchain.text-splitter [RecursiveCharacterTextSplitter
                                 MarkdownTextSplitter])
(import langchain.utilities [WikipediaAPIWrapper])
(import langchain.schema [Document])

(import .utils [config format-chat-history])
(import .interface [track spinner-context])
(import .texts [youtube->text url->text now->text])


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
;;; count ze tokenz: object.__repr__ -> int
;;; -----------------------------------------------------------------------------

(defn token-count [x]
  "The number of tokens, roughly, of a chat history (or anything with a meaningful __repr__)."
  (->> x
       (str)
       (tokenizer.encode)
       (len)))

;;; -----------------------------------------------------------------------------
;;; functions to load documents from files : fname, ? -> Documents
;;; -----------------------------------------------------------------------------

(defn unstructured->docs [fname]
  "Create list of document objects from a file of any type, using Unstructured."
  (let [loader (UnstructuredFileLoader fname)]
    (try
      (loader.load-and-split :text-splitter splitter)
      (except [ValueError]
        [False]))))

(defn textfile->docs [fname] 
  "Create list of document objects from a text file, using the tokenizer."
  ; FIXME: manage plain text not decoding with utf-8
  (-> fname
    (TextLoader)
    (.load-and-split :text-splitter splitter)))

(defn pdf->docs [fname] 
  "Create list of document objects from a pdf file."
  (-> fname
    (PyMuPDFLoader)
    (.load-and-split :text-splitter splitter)))

(defn load-audio [fname]
  "Create list of documents from audio, via whisper transcription."
  [False])

(defn file->docs [fname]
  "Intelligently (ha!) load a single file as a iterable of Document objects."
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
                (logging.warning f"Ignored: {mime} {fname}")
                [False])
              (do
                (let [disp-str f"Loading {mime} \"{fname}\""]
                  (logging.info disp-str))
                (try
                  (match mime
                      "application/pdf" (pdf->docs fname)
                      "text/plain" (textfile->docs fname)
                      otherwise (unstructured->docs fname))
                  (except [UnicodeDecodeError]
                    (logging.warning f"Failed to decode {fname} using utf-8: ignored.")
                    [False])
                  (except [e [TypeError]]
                    (logging.warning f"Failed to embed or decode {fname}: ignored.")
                    (logging.warning (repr e))
                    [False])
                  (except [e [Exception]]
                    (logging.error f"Failed with unknown error {fname}: ignored.")
                    (logging.error (repr e))
                    [False])))))))

(defn __load-file-convenience [root fname]
  (try
    (file->docs (os.path.join root fname))
    (except [e [Exception]]
      (logging.error f"Error: {fname}")
      (logging.error (repr e))
      [False])))

(defn __serial-load-files [root files]
  "Internal mapping of file->docs Use dir->docs instead."
  ;; The fast tokenizer is already parallel, so slower to parallelise this
  (let [f (partial __load-file-convenience root)]
      (->> (map f files)
           (chain.from-iterable)
           (filter None)
           (list))))

(defn dir->docs [directory]
  "Create an iterable of Document objects from all files in a directory (recursive)."
  (let [file-list (with [c (spinner-context f"Listings files")]
                    (list (os.walk directory)))]
    (gfor [root dirname files] (track file-list
                                      :description "[green italic]Ingesting files"
                                      :transient True)
          document (__serial-load-files root files)
          document)))

; TODO: think about return values; maybe track lists of ignored files?

(defn ->docs [fname]
  "Just give me an iterable of document chunks!"
  (logging.info "Listing documents.")
  (cond (os.path.isdir fname) (dir->docs fname)
        (os.path.isfile fname) (file->docs fname)
        :else (raise (FileNotFoundError fname))))

;;; -----------------------------------------------------------------------------
;;; functions to load documents from other sources : ? -> Documents
;;; -----------------------------------------------------------------------------

(defn chat->docs [chat-history topic]
  "Formats a chat history (list of message dicts) as docs."
  (let [chat-string (format-chat-history chat-history)]
    (splitter.create-documents [chat-string]
                               :metadatas [{"source" "chat"
                                            "topic" topic
                                            "time" (now->text)}])))

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
                         (url->text))]
        (splitter.create-documents [markdown]
                                   :metadatas [{"source" urls
                                                "url" urls
                                                "time" (now->text)}]))
      (chain.from-iterable (lfor u urls (url u)))))

(defn youtube->docs [youtube-id]
  "Load and punctuate youtube transcript as list of documents.
   Youtube 'transcripts' are just a long list of words with no punctuation
   or identification of the speaker, so we apply a punctuation filter.
   Youtube transcripts also tend to be long and rambling, so we will need to
   summarize them."
  (let [text (youtube->text youtube-id)
        url f"https://www.youtube.com/watch?v={youtube-id}"
        doc (Document :page-content text
                      :metadata {"source" url "youtube-id" youtube-id})]
    (splitter.split-documents [doc])))
