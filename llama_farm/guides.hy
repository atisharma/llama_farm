"
Prompts for use with guidance.

The higher-order functions herein return functions as defined by their templates.


PLAN

In the context of a topic,

- Extract relevant bullet points from text
- Pick N most important / relevant / salient bullet points from a list
- Rate relevance of a passage
- map-reduce over bullet points

- thoughts, insights, feelings etc as per agents


Use Polya's method for problem solving.

Critical thinking:
- summarize argument made
- list assumptions
- test reasonableness of assumptions
- list deductive steps from assumptions
- check reasoning of these steps


DATA MODEL

* message
  - a dict, `{\"role\" role \"bot\" bot-name \"content\" text-content}`
* chat history
  - a list of messages
* text
  - a string


"

(import guidance)
(import uuid [uuid4])

(import .utils [params config])
(import .tool-parser [describe command-parse])
(import llama-farm [tools texts])


(defn model [bot]
  "Return a model instance based on the model name only."
  (let [p (params bot)]
    (guidance.llms.OpenAI (:model-name p "gpt-3.5-turbo")
                          :api-key (:openai-api-key p "n/a")
                          :api-base (:openai-api-base p (:url p None))
                          :temperature (:temperature p 0.0)
                          :api-type "open_ai")))

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
  (.join on args)) 

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
          (chat->guidance (+ chat [user-message]))
          (assistant "{{gen 'result'}}"))))

(defn chat->topic [chat]
  "Guidance program to create a topic summary from chat history."
  (guidance
    (ncat (chat->guidance chat)
          (system "Your sole purpose is to express the topic of conversation in one short sentence.")
          (user "Summarize the topic of conversation so far in about ten words.")
          (assistant "{{gen 'result' temperature=0}}"))))

(defn chat->points [chat]
  "Guidance program to create bullet points from chat history."
  (guidance
    (ncat
      (chat->guidance chat)
      (system "Your sole purpose is to summarize the conversation into bullet points.")
      (user "Summarize this chat so far as a list of bullet points, preserving the most interesting, pertinent and important points. Write only bullet points, with no padding text.")
      (assistant "{{gen 'result' temperature=0}}"))))

(defn chat->summary [chat]
  "Guidance program to create summary from chat history."
  (guidance
    (ncat
      (chat->guidance chat)
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "Please edit down the conversation so far into a single concise paragraph, preserving the most interesting, pertinent and important points.")
      (assistant "{{gen 'result' temperature=0}}"))))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to paragraphs of text
;;; -----------------------------------------------------------------------------

(defn text->topic []
  "Guidance program to create a topic summary from text."
  (guidance
    (ncat
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "Please express the topic of the following text in less than 10 words:
---
{{input}}
---")
      (assistant "{{gen 'result' temperature=0}}"))))

(defn text->points []
  "Guidance program to create bullet points from text."
  (guidance
    (ncat
      ;(system "Your sole purpose is to summarize text into bullet points.")
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "Summarize this text as a list of bullet points, preserving the most interesting, pertinent and important points. Remove legal disclaimers and advertising.
---
{{input}}
---
Write only bullet points, with no padding text.")
      (assistant "{{gen 'result' temperature=0}}"))))

(defn text->summary []
  "Guidance program to create bullet points from text."
  (guidance
    (ncat
      (system "You are a helpful assistant who follows instructions carefully.")
      (user "Please concisely rewrite the following text, preserving the most interesting, pertinent and important points. Remove legal disclaimers and advertising.
---
{{input}}
---
")
      (assistant "{{gen 'result' temperature=0}}"))))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to combined text and chat
;;; -----------------------------------------------------------------------------

;; TODO: use something like this for chat over yt etc
(defn query&chat->reply [chat system-prompt]
  "Guidance program to respond in the context of the chat and some text.
The text should not be so long as to cause context length problems, so summarise it first if necessary."
  (guidance
    (ncat (system (:system-prompt (params bot)))
          (chat->guidance chat)
          (user "{{query}}
The following is context for your reply.
---
{{context}}
---")
          (assistant "{{gen 'result'}}"))))

(defn use-tools->reply [#* tools]
  "Guidance program to respond to a query with tools available."
  (guidance
    (ncat (system (ncat "You are a helpful, concise assistant who follows instructions carefully."
                        f"Today's date and time is {(texts.now->text)}."
                        "For information since 2020 and what you don't know, use tools."
                        "You have the following tools available."
                        #* (map describe tools)
                        :on "\n\n"))
          (user "Use the tools to get information relevant to the following prompt, supplying any parameters. Do not respond with anything else. Do not invent new tools or show examples. You may nest / substitute calls to tools.
Your prompt is:
---
{{query}}
---
")
          (assistant "{{gen 'result'}}"))
    #** (dfor t tools t.__name__ t) :command-parse command-parse))

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to logic and reasoning
;;; -----------------------------------------------------------------------------

(defn polya []
  "Apply a problem-solving approach to a puzzle, inspired by Polya's method."
  ;; ask it for the square root of pi.
  (guidance
    (ncat (system "You are a helpful, intelligent assistant who follows instructions carefully. You proceed step by step.")
          (user "Consider the following problem.
---
{{query}}
---
State the problem according to your understanding, taking care to list the unknown, the data, the constraints and conditions. You may wish to mention similar problems and their methods of solution. Make approximations if necessary.")
          (assistant "{{gen 'problem'}}") 
          (user "Using the best method of solution, make a plan that will lead to a solution.")
          (assistant "{{gen 'plan'}}") 
          (user "Carry out the plan to give a candidate solution to the problem.")
          (assistant "{{gen 'draft_solution'}}") 
          (user "Review your solution to check if it is correct. Does it satisfy the conditions, use all the data, and solve the original problem? Identify any mistakes or problems with the solution.")
          (assistant "{{gen 'review'}}") 
          (user "State your final solution to the original problem.")
          (assistant "{{gen 'solution'}}")))) 

;;; -----------------------------------------------------------------------------
;;; Applications of guidance to task management
;;; -----------------------------------------------------------------------------

;; FIXME: TODO: finish task handling and planning
;; TASK: json task description
;; Can the task be executed without splitting it into subtasks, with the tools available?
;; Can the task be split into simpler tasks?
;; Split the task into a list of subtasks.
;; Complete the following task, with the tools available. Return the result in the task template.
;; Complete the following task, with the tools available.

(setv task-examples [
                     {"id" (uuid4)
                      "parent_id" (uuid4)
                      "object_type" "task"
                      "objective" "Teach the world to sing."
                      "tools" ["tool1" "tool2" "tool3"]}])

(defn task->subtasks []
  "Guidance program to split a task into subtasks."
  (guidance
    (ncat
      (system "Your purpose is to divide tasks into a list of subtasks, in valid JSON format.")
      (user "
Here you are given a task defined in json format.
```json
{
  \"task\": \"{{task}}\",
  \"objective\": \"{{objective}}\",
  \"tools\": \"{{tools}}\",
  \"context\": \"{{context}}\"
}

Respond with a list of tasks in the same format that if all completed together, would complete the given task, keeping in mind the overall objective and context. Use one line per task.")
      (assistant "
[
  {{#geneach 'subtasks'}}
  \"{{gen 'subtask'}}\",{{/geneach}}
]
"))))
  
(defn revise-task [task-list]
  "Given a list of tasks and the current status, revise a particular task.")

(defn divide-or-conquer-task [task]
  "Determine if a task should be split into subtasks or executed.")

(defn execute-task [task-list]
  "Given a task and tools, complete a particular task.
If it cannot be completed, return an error code.")

(defn judge-task [task-list]
  "Given an executed task, determine if a task should be marked as completed
or marked for another attempt at execution.
If it has failed multiple times, return an error code.")

