"A functional collection of llama agents.

Works fairly well with llama-supercot.

Here we model a community of agents, where each agent has a different
role, or voice, related to executive functions such as attentional
control, cognitive flexibility, cognitive inhibition, inhibitory
control, working memory, and planning. The goal is to improve these
abilities through various techniques like breaking up large tasks into
smaller ones, creating schedules, and utilizing visual aids.

Data structures:

* the task list
* voice
  - prompt that determines the personality and function
  - parameters
* task
  - task completion state
  - subtasks
  - internal dialogue
* internal dialogue


Functions:

leader: tasks -> subtask, context
voice: subtask, context -> conclusion
parse: response -> command, text
search: phrase -> text
recall: keywords, db -> text
remember: text -> keywords, db-row
revise: text -> text


Ideas:

A scoring / promotion system between LLMs.

Judging output quality of the LLMs.
resource allocator (handle tasks)
director (handle aims)
marker (judge output quality)

look to swarm intelligence for inspiration?
each agent could act independently and only halt and report when stuck.

"

(require hyrule.argmove [-> ->>])
(import functools [partial])

(import agents [Personality Summarizer])
(import utils [dprint load save ->conclusion ->dict ->text rlinput])


(setv base-url "http://jupiter.letterbox.pw:5001/v1"
      params {"temperature" 0.8
              "repetition_penalty" 1.1
              "max_tokens" 1800
              "model" "default"}
      permitted-keys #{"objective" "completed" "task_list" "next_task" "constraints" "reasoning" "idea" "weaknesses" "strengths" "keywords" "context"})

;; functions on plans: plan, ... -> plan
(defn apply [agent plan [verbose False]]
  "Apply an agent to a plan and insert/update its output (if there is any)."
  (let [output-text (agent :verbose verbose #** plan)
        output-dict (->dict output-text)]
    (dprint output-dict)
    (dfor [k v] (.items (| plan output-dict))
          :if (in k permitted-keys)
          k v)))


;; the raw agents: plan -> text

(setv manage (partial apply (Personality :base-url base-url
                                         :character "I decide on the best actionable task to do next to achieve the aims. I review and revise the aims, updating them to reflect the current plan. I remove completed tasks from the aims and add new ones as necessary."
                                         :template {"thoughts" "my thinking on how to break down the objective into aims"
                                                    "completed" "a record of tasks that have already been completed."
                                                    "task_list" "a list of actionable tasks I think of that conveys the plan to meet the long-term objective."
                                                    "next_task" "the next actionable item I have decided to complete."} 
                                         :params params)))

(setv innovate (partial apply (Personality :base-url base-url
                                           :character "I give one imaginative, bright new idea for reaching the objective."
                                           :template {"opportunities" "my thoughts on opportunities for improving the plan."
                                                      "reasoning" "my reasoning."
                                                      "emotions" "how I feel about the plan."
                                                      "idea" "the new idea that might help"}
                                           :params (| params {"temperature" 1.3
                                                              "repetition_penalty" 1.3}))))

(setv reflect (partial apply (Personality :base-url base-url
                                          :character "I look for problems and pitfalls in the current plan. I am apprehensive about things that can go wrong, and seek to identify risks. I also look for the best thing in the current plan."
                                          :template {"reasoning" "my reasoning."
                                                     "weaknesses" "weaknesses in the current plan."
                                                     "strengths" "strength of the current plan."}
                                          :params params)))

(setv research (partial apply (Personality :base-url base-url
                                           :character "I suggest keywords or a search phrase that will yield the most useful information."
                                           :template {"keywords" "a useful search phrase or keywords."}
                                           :params (| params {"max_tokens" 2000}))))

(setv summarize (partial apply (Summarizer :base-url base-url
                                           :params (| params {"max_tokens" 2000
                                                              "temperature" 0.2
                                                              "repetition_penalty" 1.2}))))


; add in human input at each cycle
(defn iterate-plan [plan]
  "Iterate the context, aims and task.
The objective and constraints are invariant.
Context should be updated externally.
Iterates to a (conceptual) fixed point or limit cycle."

  (print)
  (dprint "Existing plan" (->text plan))

  ; internal dialogue
  (let [plan+ (-> plan
                  (innovate)
                  (reflect)
                  (manage)
                  (research)); TODO: replace keywords with research
        plan++ (| plan+ {"context" (rlinput "\ncontext > " (or (:context plan+ "") "None"))})]

    (print)
    (dprint "New plan" (->text plan++))

    ; allow human to update external state
    (save plan++ "plan.json")
    plan++))


; to avoid cycles, think about a tree hierarchy of objectives.

; save and load plan

; some sort of repl
