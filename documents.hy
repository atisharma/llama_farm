"
Functions that produce lists of Document objects.
"

(require hyrule.argmove [-> ->>])
(require hyrule.control [unless])

(import os)
(import magic)

(import functools [partial])
(import itertools [chain repeat])
(import multiprocessing [Pool cpu-count])

(import requests)
(import markdownify [markdownify])
(import rich [print])

; consider moving into the parallel loop after the fork
; but transformers is imported by langchain
(import transformers [LlamaTokenizerFast])

(import langchain.document-loaders [TextLoader
                                    UnstructuredFileLoader
                                    PyMuPDFLoader])
                                    
(import langchain.text-splitter [RecursiveCharacterTextSplitter
                                 MarkdownTextSplitter])

(import langchain.utilities [WikipediaAPIWrapper])

(import utils [config])

;;; TODO: logging instead of prints


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

(defn load-unstructured [fname [verbose True]]
  "Create list of document objects from a file of any type, using Unstructured."
  (let [loader (UnstructuredFileLoader fname)]
    (try
      (loader.load-and-split :text-splitter splitter)
      (except [ValueError]
        [False]))))

(defn load-text [fname [verbose True]]
  "Create list of document objects from a text file, using the tokenizer."
  ; FIXME: manage plain text not decoding with utf-8
  (-> fname
    (TextLoader)
    (.load-and-split :text-splitter splitter)))

(defn load-pdf [fname [verbose True]]
  "Create list of document objects from a pdf file."
  (-> fname
    (PyMuPDFLoader)
    (.load-and-split :text-splitter splitter)))

(defn load-audio [fname]
  "Create list of documents from audio, via whisper transcription."
  [False])

(defn load-file [fname [verbose True]]
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
                (when verbose (print f"[red]Ignored: {mime} {fname}[/red]"))
                [False])
              (do
                (when verbose
                  (let [disp-str f"{mime} \"{fname}\""]
                    (print disp-str)))
                (try
                  (match mime
                      "application/pdf" (load-pdf fname)
                      "text/plain" (load-text fname)
                      otherwise (load-unstructured fname))
                  (except [UnicodeDecodeError]
                    (print f"[red]Failed to decode {fname} using utf-8: ignored.[/red]")
                    [False])
                  (except [e [TypeError]]
                    (print f"[red]Failed to embed or decode {fname}: ignored.[/red]")
                    (print (repr e))
                    [False])
                  (except [e [Exception]]
                    (print f"[red]Failed with unknown error {fname}: ignored.[/red]")
                    (print (repr e))
                    [False])))))))

(defn __load-file-convenience [root verbose fname]
  (try
    (load-file (os.path.join root fname) :verbose verbose)
    (except [e [Exception]]
      (when verbose
        (print f"[red]Error: {fname}[/red]")
        (print (repr e)))
      [False])))

(defn __parallel-load-files [root files [verbose True]]
  "Internal, parallel mapping of load-file. Use load-dir instead.
   The number of worker threads is set as db.loader-threads in config.toml.
   The default is the number of cpus."
  ;;
  ;; FIXME: parallel tokenizer;
  ;; fast tokenizer parallel, disable since parallel at file level
  ;;
  (setv (get os.environ "TOKENIZERS_PARALLELISM") "false")
  (let [f (partial __load-file-convenience root verbose)
        threads (or (config "storage" "loader-threads") (cpu-count))]
    (with [p (Pool :processes threads)]
      (->> (p.imap-unordered f files)
           (chain.from-iterable)
           (filter None)
           (list)))))

(defn load-dir [directory [verbose True]]
  "Create an iterable of Document objects from all files in a directory (recursive)."
  (gfor [root dirname files] (os.walk directory)
        document (__parallel-load-files root files :verbose verbose)
        document))

; TODO: think about return values; maybe track lists of ignored files?

(defn load [fname [verbose True]]
  "Just give me an iterable of document chunks!"
  (when verbose (print "[blue]Loading documents.[/blue]"))
  (cond (os.path.isdir fname) (load-dir fname :verbose verbose)
        (os.path.isfile fname) (load-file fname :verbose verbose)
        :else (raise (FileNotFoundError fname))))


;;; -----------------------------------------------------------------------------
;;; functions to load documents from other sources : ? -> Documents
;;; -----------------------------------------------------------------------------

(defn wikipedia [topic]
  "Get the full Wikipedia entry on a topic, as a list of Documents."
  (-> (WikipediaAPIWrapper)
    (.load topic)
    (splitter.split-documents)))

(defn _get-url [url]
  "Fetch a URL's content as text."
  ; TODO: some error handling
  (-> url
      (requests.get)
      (. text)))

(defn url [urls [verbose True]]
  "Create single list of document objects from a list of URLs (or single URL), via markdown."
  (if (isinstance urls str) ; single url really
      (let [splitter (MarkdownTextSplitter :chunk-size (config "storage" "chunk-size-chars"))
            markdown (-> urls
                         (_get-url)
                         (markdownify :heading-style "ATX"))]
        (splitter.create-documents [markdown]
                                   :metadatas [{"source" urls "url" urls}]))
      (chain.from-iterable (lfor u urls (url u :verbose verbose)))))


;;; -----------------------------------------------------------------------------
;;; handle results : Documents -> ?
;;; -----------------------------------------------------------------------------

(defn present [docs]
  "Pretty-print a bunch of docs (e.g. from a query result)"
  (for [d docs]
    (print (* "─" 80))
    (for [[a b] (.items d.metadata)]
      (print f"[bold][magenta]{a}:[/magenta]\t[bright cyan]\"{b}\"[default]"))
    (print (* "─" 80))
    (print d.page-content)
    (print)))

(defn sources [docs]
  "The list of unique sources of documents."
  (-> (lfor d docs (get d.metadata "source"))
      (dict.fromkeys)
      (list)))
 
