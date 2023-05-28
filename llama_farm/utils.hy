(require hyrule.argmove [-> ->>])
(require hyrule.control [unless])

(import json)
(import re)
(import readline)
(import pathlib [Path])
(import hashlib [md5])
(import urllib.parse [urlparse])

;; tomllib for python 3.11 onwards
(try
  (import tomllib)
  (except [ModuleNotFoundError]
    (import tomli :as tomllib)))

(import rich)


(setv re-parser (re.compile r"([^\n][ \w]*): "))
(setv config-file "config.toml")

(defclass ResponseError [Exception])


(defn tee [x]
  (rich.inspect x)
  (rich.print x)
  x)

(defn config [#* keys]
  ; get values in a toml file like a hashmap, but default to None.
  (try
    (-> config-file
      (slurp)
      (tomllib.loads)
      (get #* keys))
    (except [KeyError]
      None)))

(defn rlinput [prompt [prefill ""]]
  "Like python's input() but using readline."
  (readline.set_startup_hook (fn [] (readline.insert_text prefill)))
  (try
    (input prompt)
    (finally
      (readline.set_startup_hook))))

(defn load [fname]
  "Read a json file."
  (with [f (open fname
                 :mode "r"
                 :encoding "UTF-8")]
    (json.load f)))

(defn save [obj fname]
  "Write an object as a json file."
  (with [f (open fname
                 :mode "w"
                 :encoding "UTF-8")]
    (json.dump obj f :indent 4)))

(defn slurp [fname]
  "Read a text file."
  (let [path (Path fname)]
    (when (path.exists)
      (path.read-text))))

(defn hash-id [s]
  "Hex digest of md5 hash of string."
  (-> (s.encode "utf-8")
      (md5)
      (.hexdigest)))

(defn is-url [url]
  "True if a plausible url."
  (let [result (urlparse url)]
    (all [result.scheme result.netloc])))

(defn msg [role content bot]
  "To conform with langchain's ridiculous BaseMessage schema."
  {"role" role
   "bot" bot
   "content" content})

(defn system [content]
  (msg "system" content "system"))

(defn user [content username]
  (msg "user" content username))

(defn inject [system-message chat-history]
  "Prepend the chat history with the system message."
  (+ [(system system-message)]
     chat-history))

;; possibly defunct - consider removing the following

(defn dprint [#* args]
  "Pretty print a bunch of args."
  (import rich)
  (for [x args]
    (rich.print (* "═" 80))
    (rich.print x))
  (rich.print (* "┈" 80)))

(defn get-response [response]
  (try
    (get response "choices" 0 "text")
    (except [KeyError]
      (let [response-str (json.dumps response :indent 4)]
        (raise (ResponseError f"Bad response format from server,\n{response-str}"))))))

(defn get-alpaca-response-text [response]
  "Get the response text of an Alpaca type response."
  (-> response
    (.split "# Response:")
    (get -1)
    (.strip)))

(defn ->conclusion [text]
  "Extract just the last section of a reply string."
  (-> text
      (.split ":")
      (get -1)
      (.strip)))

(defn ->dict [text]
  "Split output into a dictionary with a key for each section of a reply string."
  (let [pairs (->> text
                   (re-parser.split)
                   (filter None))]
    (dfor [k v] (zip pairs pairs)
       (.strip (k.lower)) (.strip v))))
  
(defn ->text [plan]
  "Turn a plan dict into text."
  (.join "\n"
         (lfor [k v] (.items plan)
               f"{(k.upper)}: {v}")))
