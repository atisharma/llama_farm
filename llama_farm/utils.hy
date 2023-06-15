(require hyrule.argmove [-> ->>])
(require hyrule.control [unless])

(import os)
(import json)
(import re)
(import readline)
(import pathlib [Path])
(import hashlib [md5])
(import urllib.parse [urlparse])

;; tomllib for python 3.11 onwards
;; when we move to 3.11, we can remove this
(try
  (import tomllib)
  (except [ModuleNotFoundError]
    (import tomli :as tomllib)))


(setv re-parser (re.compile r"([^\n][ \w]*): "))
(setv config-file "config.toml")

(defclass ResponseError [Exception])


;;; -----------------------------------------------------------------------------
;;; config functions
;;; -----------------------------------------------------------------------------

(defn config [#* keys]
  "Get values in a toml file like a hashmap, but default to None."
  (unless (os.path.isfile config-file)
    (raise (FileNotFoundError config-file)))
  (try
    (-> config-file
      (slurp)
      (tomllib.loads)
      (get #* keys))
    (except [KeyError]
      None)))

(defn bots []
  "Just a list of bots defined in the config."
  (lfor #(b v) (.items (config "bots")) :if (isinstance v dict) b))

(defn params [bot]
  "Return a dict of bot's parameters."
  (get (config "bots") (.lower bot)))

;;; -----------------------------------------------------------------------------
;;; File & IO functions
;;; -----------------------------------------------------------------------------

(defn rlinput [prompt [prefill ""]]
  "Like python's input() but using readline."
  (readline.set_startup_hook (fn [] (readline.insert_text prefill)))
  (try
    (input prompt)
    (except [EOFError]
      "/quit")
    (finally
      (readline.set_startup_hook))))

(defn load [fname]
  "Read a json file. None if it doesn't exist."
  (let [path (Path fname)]
    (when (path.exists)
      (with [f (open fname
                     :mode "r"
                     :encoding "UTF-8")]
        (json.load f)))))

(defn save [obj fname]
  "Write an object as a json file."
  (with [f (open fname
                 :mode "w"
                 :encoding "UTF-8")]
    (json.dump obj f :indent 4)))

(defn file-append [record fname]
 "Append / write a dict to a file as json.
 If the file does not exist, initialise a file with the record.
 If the file exists, append to it.
 Cobbled together from https://stackoverflow.com/a/31224105
 it overwrites the closing ']' with the new record + a new ']'.
 POSIX expects a trailing newline."
  (when fname
    (if (os.path.isfile fname)
      (with [f (open fname :mode "r+" :encoding "UTF-8")]
        (.seek f 0 os.SEEK_END)
        (.seek f (- (.tell f) 2))
        (.write f (.format ",\n{}]\n" (json.dumps record :indent 4))))
      (with [f (open fname :mode "w" :encoding "UTF-8")]
        (.write f (.format "[\n{}]\n" (json.dumps record :indent 4)))))))

(defn slurp [fname]
  "Read a text file."
  (let [path (Path fname)]
    (when (path.exists)
      (path.read-text))))

;;; -----------------------------------------------------------------------------
;;; Other utility functions
;;; -----------------------------------------------------------------------------

(defn tee [x]
  (import rich)
  (rich.inspect x)
  (rich.print x)
  x)

(defn hash-id [s]
  "Hex digest of md5 hash of string."
  (-> (s.encode "utf-8")
      (md5)
      (.hexdigest)))

(defn short-id [x]
  "First 6 chars of hash-id."
  (cut (hash-id x) 6))

(defn is-url [url]
  "True if a plausible url."
  (let [result (urlparse url)]
    (all [result.scheme result.netloc])))

;;; -----------------------------------------------------------------------------
;;; Message and chat functions
;;; -----------------------------------------------------------------------------

(defn msg [role content bot]
  "To conform with langchain's ridiculous BaseMessage schema."
  {"role" role
   "bot" (.lower bot)
   "content" content})

(defn system [content]
  (msg "system" content "system"))

(defn user [content username]
  (msg "user" content username))

(defn assistant [content]
  (msg "assistant" content "assistant"))

(defn inject [system-message chat-history]
  "Prepend the chat history with the system message."
  (+ [(system system-message)]
     chat-history))

(defn format-chat-history [chat-history]
  "Format the chat history for saving to the store."
  ;; this is not in .interface with the other formatters
  ;; because it relates to the storage
  (.join "\n"
         (lfor m chat-history
               f"{(:bot m)}: {(:content m)}")))

(defn format-docs [docs]
  "Format a list of Document objects"
  (.join "\n"
         (lfor d docs f"{(:source d.metadata "")}
{(:time d.metadata "---")}
{d.page-content}")))

;;; -----------------------------------------------------------------------------
;;; String functions
;;; -----------------------------------------------------------------------------

(defn indent [s [prefix "  "]]
  "Indent a string on each line with the prefix."
  (.join "\n"
         (lfor l (.split s)
               (+ prefix l))))
