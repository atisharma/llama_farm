"
Convert, then break up large documents on sensible boundaries.
"

(require hyrule [of unless -> ->>]) 
(require hyjinx [rest lmap])

(import hyjinx [first last second flatten slurp])

(import re)
(import magic)

(import marker.convert [convert-single-pdf get-length-of-text])
(import marker.models [load-all-models :as load-marker-models])

(import markdownify [markdownify])

(import transformers [AutoTokenizer])
(import sentence-transformers [SentenceTransformer])

(import llama-farm.utils [config])


;; TODO : transcribe audio
;; TODO : CLIP to encode images

(setv ignored-extensions ["log" "dat" "aux" "icon" "tikz" "gitignore"
                          "tmp" "temp" "bkp" "dropbox"
                          "mp4" "mkv" "mov" "avi" "wmv" "flv" "webm" "mpeg" "mpg" ; movies
                          "mp3" "flac" "aac" "webm" "aiff" "wav" "ogg" "wma" "m4a" ; audio
                          "md5" "sha256" "sha512"])

(setv ignored-mime-types ["inode" "image" "video" "audio"])

(setv ignored-mime-subtypes ["octet-stream"
                             "zlib"
                             "x-git" "zip" "x-rar" "gzip" "x-bzip2"
                             "x-bytecode.python"
                             "x-ole-storage"
                             "vnd.oasis.opendocument.spreadsheet"
                             "vnd.microsoft.portable-executable"])

;; I think this causes a memory leak if the module is reloaded
(setv marker-models (load-marker-models))

(setv embedding-model (SentenceTransformer
                        (config "storage" "model")
                        :trust-remote-code (or (config "storage" "trust_remote_code") False)))

(setv tokenizer (AutoTokenizer.from-pretrained
                  (config "storage" "model")
                  :trust-remote-code (or (config "storage" "trust_remote_code") False)))


;; * High-level convenience functions
;; ----------------------------------------------------

(defn token-count [x]
  "The number of tokens, roughly, of anything with a meaningful __repr__."
  (-> x
      (str)
      (tokenizer.tokenize :padding False)
      (len)))

(defn splitter-by-extension [ext]
  "Return the splitting strings associated with the file extension."
  ;; see https://github.com/langchain-ai/langchain/blob/master/libs/text-splitters/langchain_text_splitters/character.py#L120
  (let [paras ["\n\n\n" "\n\n" "\n" "\t" " " ""]]
    (match ext
           ;; programming languages
           "c" (splitter-by-extension "cpp")
           "c++" (splitter-by-extension "cpp")
           "cpp" ["\nclass " "\nvoid "
                  "\nint " "\nfloat " "\ndouble "
                  "\nif " "\nfor " "\nwhile " "\nswitch " "\ncase "
                  #* paras]
           "go" ["\nfunc " "\nvar " "\nconst " "\ntype " "\nif " "\nfor " "\nswitch " "\ncase " #* paras]
           "hs" ["\nmain :: " "\nmain = " "\nlet " "\nin " "\ndo " "\nwhere " "\n:: " "\n= "
                 "\ndata " "\nnewtype " "\ntype " "\n:: "
                 "\nmodule " "\nimport " "\nqualified " "\nimport qualified "
                 "\nclass " "\ninstance " "\ncase " "\n| "
                 "\ndata " "\n= {" "\n, "
                 #* paras]
           "hsc" (splitter-by-extension "hs")
           "java" ["\nclass " "\npublic " "\nprotected " "\nprivate " "\nstatic "
                   "\nif " "\nfor " "\nwhile " "\nswitch " "\ncase "
                   #* paras]
           "jl" ["\nfunction " "\nconst " "\nmacro " "\nstruct " #* paras]
           "js" ["\nfunction " "\nconst " "\nlet " "\nvar " "\nclass "
                 "\nif " "\nfor " "\nwhile " "\nswitch " "\ncase "
                 "\ndefault " #* paras]
           "lua" ["\nlocal " "\nfunction " "\nif " "\nfor " "\nwhile " "\nrepeat " #* paras]
           "php" ["\nfunction " "\nclass "
                  "\nif " "\nforeach " "\nwhile " "\ndo " "\nswitch " "\ncase "
                  #* paras]
           "py" ["\nclass " "\ndef " "\n\tdef " #* paras]
           "rb" ["\ndef " "\nclass " "\nif " "\nunless " "\nwhile " "\nfor " "\ndo " "\nbegin " "\nrescue " #* paras]
           "sh" [r"\n[::alphanum::_ ]+\(" "for " "if " #* paras]
           "sql" ["\n\n\n--" "\nSELECT " "\nUPDATE " "\nDELETE " "\nINSERT " "\nCREATE " "\nALTER " "\nDROP "
                  "\nselect " "\nupdate " "\ndelete " "\ninsert " "\ncreate " "\nalter " "\ndrop "
                  #* paras]

           ;; * lisp-like
           "clj" ["\n\n\n;;; " "\n\n\n;; " r"\n\(defn " r"\n\(defmulti " r"\n\(defn- " r"\n\(def " r"\n\(def" r"\n\s+\(def" "\n;;;" "\n;;" #* paras]
           "fnl" ["\n\n\n;;; " "\n\n\n;; " r"\n(fn " r"\n\(macro " r"\n\(local " #* paras]
           "hy" ["\n\n\n;;;" "\n\n\n;; " r"\n\(defn " r"\n\(defclass " r"\n\(def" r"\n\s+\(def" "\n;;;" "\n;;" #* paras]
           "lisp" ["\n\n\n;;; " "\n\n\n;; " r"\n\(defun " r"\n\(defclass " r"\n\(defmethod " r"\n\(defmacro " r"\n\(def" r"\n\s+\(def" r"\n\(let " "\n;;;" "\n;;" #* paras]

           ;; markup languages
           "html" ["<body" "<div" "<p" "<br" "<li"
                   "<h1" "<h2" "<h3" "<h4" "<h5" "<h6"
                   "<span" "<table"
                   "<tr" "<td" "<th"
                   "<ul" "<ol"
                   "<header" "<footer"
                   "<nav" "<head"
                   "<style" "<script" "<meta" "<title"
                   #* paras]
           "tex" [r"\n\\chapter{" r"\n\\section{" r"\n\\subsection{" r"\n\\subsubsection{"
                  r"\n\\begin{enumerate" r"\n\\begin{itemize"
                  r"\n\\begin{description" r"\n\\begin{list"
                  r"\n\\begin{quote" r"\n\\begin{quotation"
                  r"\n\\begin{verse" r"\n\\begin{verbatim"
                  r"\n\\begin{align"  r"\n\\begin{equation" r"\n\\begin{eqnarray" 
                  r"\n\\\["
                  #* paras]

           ;; plaintext markup languages
           ;; markdown requires space after heading defn, ignores ***, ---
           "md" ["\n#{1,6} " "```\n" "\n\\*\\*\\*+\n" "\n---+\n" "\n___+\n" #* paras]
           "markdown" (splitter-by-extension "markdown")
           "rst" ["\n=+\n" "\n-+\n" "\n\\*+\n" "\n\n.. *\n\n" #* paras]
           "txt" paras)))

(defn filetype [fname]
  "Guess the file type from various cues.
  Return mime type and extension."
  (let [mime (magic.from-file fname :mime True)
        [mime-type mime-subtype] (.split mime "/")
        extension (last (.split fname "."))
        ignore (or (in mime-type ignored-mime-types)
                   (in mime-subtype ignored-mime-subtypes)
                   (in extension ignored-extensions)
                   (in "/.git/" fname)
                   (in "/.svn/" fname)
                   (in "/.venv/" fname)
                   (in "/__pycache__/" fname))]
    {"ignore" ignore
     "mime_type" mime-type
     "mime_subtype" mime-subtype
     "mime" mime
     "extension" extension
     "filename" fname}))

(defn split [fname * [length None]]
  "Split according to file type."
  (let [ft (filetype fname)
        length (or length embedding-model.max-sequence-length)]
    (if (:ignore ft)
        {"mime" (:mime ft)
         "filename" fname
         "fragments" []}
        {"mime" (:mime ft)
         "filename" fname
         "fragments" (flatten
                       (match (:mime ft)
                              "application/pdf" (pdf fname :length length)
                              "application/postscript" (postscript fname :length length)
                              "application/x-mobipocket-ebook" (mobi fname :length length)
                              "application/mobi" (mobi fname :length length)
                              "application/vnd.ms-xpsdocument" (xps fname :length length)
                              "application/x-fictionbook+xml" (fb2 fname :length length)
                              "application/epub+zip" (epub fname :length length)

                              "text/csv" (csv fname :length length)
                              "application/json" (json fname :length length)
                              "application/xml" (xml fname :length length)

                              "text/html" (html fname :length length)
                              "text/javascript" (split-on-chars (slurp fname)
                                                                (splitter-by-extension "js")
                                                                :length length)
                              "text/x-shellscript" (split-on-chars (slurp fname)
                                                                   (splitter-by-extension "sh")
                                                                   :length length)
                              "application/x-sh" (split-on-chars (slurp fname)
                                                                 (splitter-by-extension "sh")
                                                                 :length length)

                              "application/rtf" (rtf fname :length length)

                              "text/plain" (split-on-chars (slurp fname)
                                                           (splitter-by-extension (:extension ft))
                                                           :length length)

                              ;; take a swing and hope
                              otherwise (split-on-chars (slurp fname)
                                                        (splitter-by-extension (:extension ft))
                                                        :length length)))})))

;; * Plain-text
;; ----------------------------------------------------

(defn split-on-chars [#^ str text #^ (of list str) separators * length]
  "Recursively bisect on a character until each fragment is under the appropriate length."
  (if (and separators (>= (token-count text) length))
    (let [sep (first separators)
          occurrences (lfor m (re.finditer sep text) (.start m))
          point (if occurrences
                    (get occurrences (// (len occurrences) 2))
                    0)
          sections [(cut text point) (cut text point None)]]
      ;; if the split works, walk down the tree,
      ;; otherwise try the next separator
      (if point
          ;(print f"SPLIT ON {sep}  {(len text)} -> {(len (first sections))} + {(len (second sections))}")
          (lfor s sections :if s (split-on-chars s separators :length length))
          ;(print f"FAIL: SPLIT ON {sep}"
          (split-on-chars text (rest separators) :length length)))
    [text]))


;; * Plain-text markup flavours
;; ----------------------------------------------------

(defn html [text * length]
  "Convert html to markdown, then process."
  (-> text
      (markdownify :heading-style "ATX" :strip "style")
      (split-on-chars (splitter-by-extension "md")
                      :length length)))

;; * Data languages
;; ----------------------------------------------------

(defn json [text * length]
  (raise NotImplementedError))


;; * PDF, postscript, mobi and epub -- pymupdf can handle all these
;; ----------------------------------------------------

(defn marker [fname * length [min-text-length 10]]
  "Use marker to process the file to markdown, then split it."
  (let [text-length (get-length-of-text fname)]
    (when (> text-length min-text-length)
      (let [[full-text metadata] (convert-single-pdf fname marker-models)]
        ;; The metadata contains some info about success / failure
        ;; and the toc. We can't use it in a vector db, so discard it.
        (split-on-chars full-text
                        (splitter-by-extension "md")
                        :length length)))))

(defn postscript [fname * length]
  "Convert to pdf, then process."
  ;; I can't be bothered to call ghostscript
  ;; Anyway, who uses postscript nowadays?
  (raise NotImplementedError))
  
(defn pdf [fname * length]
  (marker fname :length length))
(defn epub [fname * length]
  (marker fname :length length))
(defn mobi [fname * length]
  (marker fname :length length))
