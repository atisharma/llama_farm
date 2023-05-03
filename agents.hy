"LLM agents.

An agent in artificial intelligence refers to a software program that
performs tasks on behalf of another entity.  Agents are designed to
act autonomously and make decisions based on their programming or
instructions from other agents.  They can be used for various purposes
such as data collection, problem solving, decision making, and
communication with other systems.  "

(require hyrule.argmove [-> ->>])

(import api [completion chat-completion edits embedding])
(import utils [get-response get-alpaca-response-text dprint])

(import rich)


(defclass BaseAgent []
  "An agent is the thing that applies an instruction to the input using the LLM server."

  (defn __init__ [self * base-url params]
    (setv self.base-url base-url
          self.params params))

  (defn complete [self prompt]
      (completion self.base-url prompt #** self.params))

  (defn __call__ [self #* args #** kwargs]
    (-> (self.complete #* args #** kwargs)
        get-response
        get-alpaca-response-text)))


(defclass AlpacaV0Agent [BaseAgent]
  "An agent is the thing that performs an instruction using the LLM server.
Assume Alpaca v0 format."

  (defn complete [self instruction]
    "Send an Alpaca-like query (v0, ###-form) to the API."
    (let [query (.join "\n"
                       ["Below is an instruction that describes a task. Write a response that appropriately completes the request."
                        "## Instruction:" instruction
                        "## Response:"])]
      (dprint query self.params self.base-url)
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
      (dprint query self.params self.base-url)
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
  "A personality is an agent with a set of parameters and a character."

  (defn __init__ [self * base-url character params]
    (setv self.base-url base-url
          self.params params
          self.character character
          self.prompt "Complete the template with your own thoughts to align with the objective, context and task. Each section has its own line." 
          self.response-template (.join "\n"
                                        ["THOUGHTS: my thoughts."
                                         "REASONING: my reasoning."
                                         "EMOTIONS: how I feel."
                                         "AIMS:\n- a short bulleted\n- list of actionable tasks that conveys\n- a long-term plan."
                                         "CRITICISM: constructive self-criticism."
                                         "ACTION: the next actionable item."])))

  (defn complete [self * objective context aims task]
    (let [instruction f"{context}
Your character: {self.character}
Your objective: {objective}
Current aims: {aims}
current task: {task}
{self.prompt}"]
      (edits self.base-url
             instruction
             self.response-template
             #** self.params))))
