"LLM agent classes.

An agent performs tasks on behalf of another entity.
Agents are designed to act autonomously and make decisions based on their
programming or instructions from other agents."


(require hyrule.argmove [-> ->>])

(import api [completion chat-completion edits embedding])
(import utils [get-response get-alpaca-response-text ->text dprint])


(defn make-template-str [template]
  "Make a template string from a template dict. A template has the format:
    {\"thoughts\" \"THOUGHTS: my thoughts\"
    \"reasoning\" \"REASONING: my reasoning\"
    \"emotions\" \"EMOTIONS: how I feel\"}"
  (.join "\n"
         (lfor [k v] (template.items)
               f"{(.upper k)}: {v}")))
  

(defclass BaseAgent []
  "An agent is the thing that applies an instruction to the input using the LLM server."

  (defn __init__ [self * base-url [params {}]]
    (setv self.base-url base-url
          self.params params))

  (defn complete [self prompt]
      (completion self.base-url prompt #** self.params))

  (defn _clean-response [self response]
    (-> response
        get-response
        get-alpaca-response-text))

  (defn __call__ [self #* args [verbose False] #** kwargs]
    (let [full-response (self.complete #* args #** kwargs)
          response (self._clean-response full-response)]
      (when verbose
        (print (* "=" 80))
        (print response)
        (print (* "=" 80)))
      response)))


(defclass AlpacaV0Agent [BaseAgent]
  "An agent is the thing that performs an instruction using the LLM server.
Assume Alpaca v0 format."

  (defn complete [self instruction]
    "Send an Alpaca-like query (v0, ###-form) to the API."
    (let [query (.join "\n"
                       ["Below is an instruction that describes a task. Write a response that appropriately completes the request."
                        "## Instruction:" instruction
                        "## Response:"])]
      (completion self.base-url query #** self.params))))


(defclass AlpacaV0InputAgent [BaseAgent]
  "An agent is the thing that applies an instruction to the input using the LLM server.
Assume Alpaca v0 format."

  (defn complete [self * instruction input]
    "Send an Alpaca-like query (v0, ###-form) to the API."
    (let [query (.join "\n"
                       ["Below is an instruction that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request."
                        "## Instruction:" instruction
                        "## Input:" input
                        "## Response:"])]
      (completion self.base-url query #** self.params))))


(defclass Summarizer [AlpacaV0InputAgent]
  "Summarizes the given text."

  (defn complete [self text]
    (let [query (.join "\n"
                       ["Below is an instruction that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request."
                        "## Instruction: Briefly summarize the input text."
                        f"## Input: {text}"
                        "## Response:"])]
      (completion self.base-url query #** self.params))))


(defclass Personality [BaseAgent]
  "A personality is an agent with a set of parameters and a character.
It thinks in terms of form-filling of templates."

  (setv template {"thoughts" "my thoughts."
                  "reasoning" "my reasoning."
                  "emotions" "how I feel."
                  "task_list" "a short list of actionable tasks that conveys a long-term plan."
                  "criticism" "constructive self-criticism."
                  "next_task" "the next actionable item."})
        
  (defn __init__ [self * base-url character params [template None]]
    (when template (setv self.template template))
    (setv self.base-url base-url
          self.params params
          self.character character
          self.prompt "Next, complete the template with your own thoughts to align with the objective. Each section has its own line.")) 

  (defn complete [self #** kwargs]
    (let [instruction (->text kwargs)]
      (edits self.base-url
             (.join "\n" [self.character
                          instruction
                          self.prompt])
             (make-template-str self.template)
             #** self.params))))
