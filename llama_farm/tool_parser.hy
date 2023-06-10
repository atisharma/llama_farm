"
Parse tool commands in text.
Valid tools must be functions defined in tools.hy.
Tools are called with the syntax `[[tool args]]`.
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
  f"tool: {f.__name__}
Description: {f.__doc__}")

(defn contains-command [s]
  "True if string has command markers in."
  (and (in "[[" s)
       (in "]]" s)))

;; TODO: don't match literal code blocks ``xyz`` https://regex101.com/r/fubH7e/1
(defn command-parse [s]
  "A recursive descent parser in lisp style."
  (let [m (re.search r"(\[\[[^\[\]]+]])" s re.MULTILINE)] ; match "[[command args]]" syntax
    (if m
        (let [atom (get (.groups m) 0)]
          (->> atom
               (command-eval)
               (.replace s atom) ; this is not a mistake
               (command-parse)))
        s)))

(defn command-eval [s]
  "Apply a tool to evaluate the string s, where s is of the form `[[command args]]`.
Without the use of eval."
  (let [avail-commands (dict (inspect.getmembers tools inspect.isfunction))
        atomic-command (get (.groups (re.search r"\[\[([^\[\]]+)]]" s re.MULTILINE)) 0)
        [uncased-command _ args] (.partition atomic-command " ")
        command (.lower uncased-command)]
    (if (in command avail-commands)
        (try
          ((get avail-commands command) args)
          (except [e [Exception]]
            f"[ERROR evaluating {command} {args}; {(repr e)}]"))
        f"[{atomic-command} is not defined.]")))
