"
Parse tool commands in text.
Valid functions must be defined in tools.hy.
"

(require hyrule.argmove [-> ->> as->])

(import re)
(import inspect)

(import llama-farm [tools])


;;; -----------------------------------------------------------------------------
;;; Tool parser and utility functions
;;; -----------------------------------------------------------------------------

(defn describe [f]
  "Return a string with the description of the function f (a tool)."
  (let [f-desc (.join "\n; " (.split f.__doc__ "\n"))
        f-args (.join " " (get (inspect.getargspec f) 0))]
    f"; function {f.__name__}
; {f-desc}
(define ({f.__name__} {f-args})
  ; returns the output
  )"))

(defn contains-command [s]
  "True if string has command markers in."
  (and (in "(" s)
       (in ")" s)))

;; TODO: don't match literal code blocks ``xyz`` https://regex101.com/r/fubH7e/1
(defn command-parse [s]
  "A recursive descent parser in lisp style."
  ;(let [m (re.search r"(\[\[[^\[\]]+]])" s re.MULTILINE)] ; match "[[command args]]" syntax
  ; match "(command args)" syntax
  (let [m (re.search r"(\([^\(\)]+\))" s re.MULTILINE)]
    (if m
        ; replace the first match with its evaluation
        (let [atom (get (.groups m) 0)]
          (->> atom
               (command-eval)
               (.replace s atom)
               (command-parse)))
        (-> s
            (.replace "==[[" "(")
            (.replace "]]==" ")")))))

(defn command-eval [s]
  "Apply a tool to evaluate the string s, where s is of the form `(command args)`.
Without the use of eval."
  (let [avail-commands (dict (inspect.getmembers tools inspect.isfunction))
        match (re.search r"\((.*)\)" s re.MULTILINE)]
    (if match
        (let [atomic-command (get (.groups match) 0)
              [uncased-command _ args] (.partition atomic-command " ")
              command (.lower uncased-command)]
          (if (in command avail-commands)
              (try
                ((get avail-commands command) args)
                (except [e [Exception]]
                  f"[ERROR evaluating ==[[{command} {args}]]==; {(repr e)}]"))
              f"==[[{atomic-command}]]=="))
        f"==[[None]]==")))

(defn extract-json [s]
  "Extract the first valid json string if there's one in there.")
