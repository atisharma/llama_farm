"
Prompts for use with guidance.

The higher-order functions herein return functions as defined by their templates.

FIXME: Programs fail badly when the server returns a response with no content.
       Somehow handle retries or something when this happens.

TODO:
In the context of a topic,
- Rate relevance of a passage
- thoughts, insights, feelings etc as per agents

TODO:
Critical thinking:
- summarize argument made
- list assumptions
- test reasonableness of assumptions
- list deductive steps from assumptions
- check reasoning of these steps


DATA MODEL

* message
  - a dict, `{\"role\" role
              \"bot\" bot-name
              \"content\" text-content}`
* chat history
  - a list of messages
* text
  - a string
"

(import itertools)
(import sys)
(import json)

(import guidance)
;; horrible hack for https://github.com/microsoft/guidance/issues/219
(defn print-to-stderr [#* args #** kwargs]
  "Print to stderr unless specified."
  (with [log-file (open "guidance.stderr" "w")]
    (let [file (.pop kwargs "file" log-file)]
      (print #* args
             :file log-file
             #** kwargs))))
(setv guidance._program-executor.print print-to-stderr)
(setv guidance._program.print print-to-stderr)

(import lorem)

(import llama-farm [texts])
(import .tool-parser [describe command-parse])
(import .utils [params config])


(defn model [bot]
  "Return a model instance based on the model name only."
  ; TODO: implement a human-input model
  (let [p (params bot)]
    (if (in (.lower (:kind p "mock"))
            ["openai" "local"])
        (guidance.llms.OpenAI (:model-name p "gpt-3.5-turbo")
                              :api-key (:openai-api-key p "n/a")
                              :api-base (:openai-api-base p (:url p None))
                              :temperature (:temperature p 0.5)
                              :api-type "open_ai"
                              :caching (config "cache"))
        (guidance.llms.Mock (lorem.get-word :count 200))))) 

;;; -----------------------------------------------------------------------------
;;; Utility functions
;;; -----------------------------------------------------------------------------

(defn system [text]
  "System prompt in guidance format"
  (.join "\n"
         ["{{#system~}}"
          text
          "{{~/system}}\n"]))

(defn user [text]
 "User prompt in guidance format"
 (.join "\n"
        ["{{#user~}}"
         text
         "{{~/user}}\n"]))

(defn assistant [text]
  "Assistant prompt in guidance format"
  (.join "\n"
         ["{{#assistant~}}"
          text
          "{{~/assistant}}\n"]))

(defn ncat [#* args [on "\n"]]
  "Join a bunch of strings on newline char (or whatever)."
  (.join on (filter None args))) 

(defn chat->guidance [chat]
  "Put chat history in guidance string format."
  (.join "\n"
         (gfor m chat
               (+ "{{#" (:role m) "~}}\n"
                  (:content m)
                  "{{~/" (:role m) "}}\n"))))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to chat history
;;; -----------------------------------------------------------------------------

(defn chat->reply [chat user-message system-prompt]
  "Guidance program to create a simple chat reply from the chat history."
  (guidance
    (ncat (system system-prompt)
          (chat->guidance chat)
          (user (:content user-message))
          (assistant "{{gen 'result'}}"))))

(defn chat->topic [chat]
  "Guidance program to create a topic summary from chat history."
  (guidance
    (ncat (system "Your sole purpose is to express the topic of conversation in one short sentence.")
          (chat->guidance chat)
          (user "Summarize the topic of conversation so far in about ten words.")
          (assistant "{{gen 'result'}}"))))

(defn chat->points [chat]
  "Guidance program to create bullet points from chat history."
  (guidance
    (ncat
      (system "Your sole purpose is to summarize the conversation into bullet points.")
      (chat->guidance chat)
      (user "Summarize this chat so far as a list of bullet points, preserving the most interesting, pertinent and important points. Write only bullet points, with no padding text.")
      (assistant "{{gen 'result'}}"))))

(defn chat->summary [chat]
  "Guidance program to create summary from chat history."
  (guidance
    (ncat
      (system "You are a helpful assistant who follows instructions carefully.")
      (chat->guidance chat)
      (user "Please edit down the conversation so far into a single concise paragraph, preserving the most interesting, pertinent and important points.")
      (assistant "{{gen 'result'}}"))))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to paragraphs of text
;;; -----------------------------------------------------------------------------

(defn text->topic []
  "Guidance program to create a topic summary from text."
  (guidance
    (ncat
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "Please express the topic of the following text in less than 10 words:

{{input}}")
      (assistant "{{gen 'result'}}"))))

(defn text->points []
  "Guidance program to create bullet points from text."
  (guidance
    (ncat
      ;(system "Your sole purpose is to summarize text into bullet points.")
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "Summarize the following text as a list of bullet points, preserving the most interesting, pertinent and important points. Remove legal disclaimers and advertising. If there is no relevant information, reply with '[removed]'.

{{input}}

Write only bullet points, with no padding text.")
      (assistant "{{gen 'result'}}"))))

(defn text->summary []
  "Guidance program to create short summary from text."
  (guidance
    (ncat
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "Please concisely rewrite the following text, preserving the most interesting, pertinent and important points. Remove legal disclaimers and advertising. If there is no relevant information, reply with '[removed]'.

{{input}}

")
      (assistant "{{gen 'result'}}"))))

(defn text->extract []
  "Guidance program to extract points relevant to a query from text."
  (guidance
    (ncat
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "{{query}}
Please concisely rewrite the following text, extracting the points most interesting, pertinent and important to the preceding question. Don't invent information. If there is no relevant information, reply with '[removed]'.

{{input}}

")
      (assistant "{{gen 'result'}}"))))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to combined text and chat
;;; -----------------------------------------------------------------------------

(defn text&chat->reply [chat]
  "Guidance program to respond in the context of the chat and some text.
The text should not be so long as to cause context length problems, so summarise it first if necessary."
  (guidance
    (ncat (chat->guidance chat)
          (user "{{query}}

Consider the following additional context before responding:
<context>
{{input}}
</context>")
          (assistant "{{gen 'result'}}"))))

;;; -----------------------------------------------------------------------------
;;; Use of tools with guidance
;;; Anything below this line is a bit hit-and-miss
;;; -----------------------------------------------------------------------------

(defn tools? [#* tools]
  "Guidance program to respond to a query with a list of suitable tools available."
  (guidance
    (ncat
      (system (ncat "You are a helpful, concise assistant who follows instructions carefully."
                   f"Today's date and time is {(texts.now->text)}."
                   "For information since 2020 and what you don't know, use the following tools.\n"
                   (ncat #* (map describe tools) :on "\n\n")))
      (user (ncat "Give all data variables that you will require to respond the query below."
                  "Respond with a list of the most pertinent variables, like:"
                  "( \"var-a\" \"var-b\" )"
                  "Do not respond to the query yet."
                  "=== QUERY ==="
                  "{{query}}."
                  "==="))
      (assistant "{{gen 'data'}}")
      (user (ncat "Give a list of the most pertinent tools calls that you will require to respond to the query, like."
                  "( \"foo\", \"bar\" )"
                  "Do not respond to the query yet."))
      (assistant "{{gen 'result'}}"))
    #** (dfor t tools t.__name__ t)))

; seems to work OK
; it might be easier just to let it execute python code in a venv.
(defn query->tools [#* tools]
  "Guidance program to use tools to get relevant info."
  (guidance
    (ncat (system (ncat "You are a helpful assistant who follows instructions carefully. You write only concise, minimal code. Where you cannot answer, you say 'no answer'."
                        f"Today's date and time is {(texts.now->text)}."
                        "For data since 2020 and what you don't know, use the following tools.\n"
                        (ncat #* (map describe tools) :on "\n\n")))
          (user (ncat "The query is:\n"
                      "{{query}}\n"
                      "Give a list only the pertinent data variables that you will require to respond the query above."
                      "Then, give a list only the pertinent tools names that you will require to respond the query."
                      "Respond with nothing else but the minimal lists of variables, then tools. Do not respond to the query itself yet."))
          (assistant "{{gen 'plan'}}")
          (user "Finally, to get the information that answers the query, apply the tools to the variables to make expressions which I will execute. You only have the tools shown earlier. Do not show examples. Do not respond to the query yet.")
          (assistant "{{gen 'program'}}"))
    #** (dfor t tools t.__name__ t)))

(defn extract-json []
  "Guidance program to extract json."
  (guidance
    (ncat (system (ncat "You are a helpful and concise assistant who follows instructions carefully."
                        "You respond only in JSON strings complying with RFC 7159."
                        "Your purpose is to extract valid json from provided input."))
          (user "{{input}}")
          (assistant "{{gen 'result'}"))))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to logic and reasoning
;;; -----------------------------------------------------------------------------

(defn polya [#* tools]
  "Apply a problem-solving approach to a puzzle, inspired by Polya's method."
  ;; ask it for the square root of pi.
  (guidance
    (ncat (system (ncat "You are a helpful, intelligent assistant who follows instructions carefully. You proceed step by step."
                        "For data since 2020 and what you don't know, use tools."
                        "You have the following tools available.\n"
                        (ncat #* (map describe tools) :on "\n\n")))
          (user "Consider the following problem:

{{query}}

State the problem according to your understanding, taking care to list the unknown, the data, the constraints and conditions. You may wish to mention similar problems and their methods of solution. Make approximations if necessary.")
          (assistant "{{gen 'problem'}}") 
          (user "Using the best method of solution, make a plan that will lead to a solution.")
          (assistant "{{gen 'plan'}}") 
          (user "Carry out the plan to give a candidate solution to the problem.")
          (assistant "{{gen 'draft_solution'}}") 
          (user "Review your solution to check if it is correct. Does it satisfy the conditions, use all the data, and solve the original problem? Identify any mistakes or problems with the solution.")
          (assistant "{{gen 'review'}}") 
          (user "State your final solution to the original problem.")
          (assistant "{{gen 'result'}}")) 
    #** (dfor t tools t.__name__ t)))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to task management
;;; -----------------------------------------------------------------------------

(defn format-task [task]
  (let [task-to-print (.copy task)]
    (.pop task-to-print "subtasks" None)
    (.pop task-to-print "assigned" None)
    (json.dumps task-to-print :indent 4)))

(defn manage-task [] ; -> "DIVIDE", "ATTEMPT", "ESCALATE", "REVISE", "ABANDON", "ACCEPT"
  "Determine if a task should be split into subtasks, attempted, revised, or abandoned."
  (guidance
    (ncat
      (system "Your purpose is to determine the appropriate action for a task, keeping in mind the overall objective. You may reply with only one word.")
      (user "Decide the best action for the following task to complete it and work towards the objective.

You may accept the task if its output fully completes the task and the output is not further tasks. Think critically.
If the output is a list of subtasks, or the task can be profitably split up, divide the task into smaller subtasks that together, would complete the task.
You may attempt the task if it is simple enough to complete and has no output yet.
Retry the task if its existing output is unsatisfactory.
Remove the task if it is redundant.
Revise the task if it's badly specified.
Abandon the task if it works against the objective
Escalate the task where it is too difficult or you need human input.

The task, expressed in JSON, is:

{{format_task task}}

Respond with the single most appropriate of the following words:

DIVIDE
ATTEMPT
RETRY
REMOVE
REVISE
ABANDON
ACCEPT
ESCALATE
")
      (assistant "{{gen 'result'}}"))
    :format_task format-task
    :caching False))

(defn divide-task [] ; -> list of tasks
  "Guidance program to split a task into subtasks."
  (guidance
    (ncat
      (system "Your purpose is to divide tasks into a list of subtasks, one per line.")
      (user "{{format_task task}}

Respond with a list of sub-tasks that if all completed together, would complete the given task, keeping in mind the overall objective, most important first. Use one bullet point per task.")
      (assistant "{{gen 'result'}}"))
    :format_task format-task
    :caching False))
  
(defn revise-task [] ; -> task
  "Given a task and the current status, revise a particular task."
  (guidance
    (ncat
      (system "Your purpose is to revise a task instruction to better achieve its purpose, in light of the context.")
      (user "{{format_task task}}

Revise the task in light of the context. Respond with one phrase which is the revised task only.")
      (assistant "{{gen 'result'}}"))
    :format_task format-task
    :caching False))

(defn attempt-task [] ; -> task output
  "Given a task and tools, attempt a particular task.
If it cannot be completed, return an error."
  (guidance
    (ncat
      (system "Your purpose is to attempt the following task.")
      (user "{{format_task task}}")
      (user "Respond with an output that completes the task.")
      (user "Respond with an output that completes the task.
If you cannot complete the task immediately, respond with 'FAILED: (error description)'.
If you can complete the task immediately, respond with the output only.")
      (assistant "{{gen 'result'}}"))
    :format_task format-task
    :caching False))

(defn retry-task [] ; -> task output
  "Given a task, tools, retry a particular task.
If it cannot be completed, return an error."
  (guidance
    (ncat
      (system "Your purpose is to retry the following task.")
      (user "{{format_task task}}

Respond with a new output that completes the task.
If you cannot complete the task immediately, respond with 'FAILED: (error description)'.
If you can complete the task immediately, respond with the output only.")
      (assistant "{{gen 'result'}}"))
    :format_task format-task
    :caching False))
