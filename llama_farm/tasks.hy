"
Divide and conquer task planner.

We define a task tree with the objective as the root and atomic completable tasks as leaf nodes.

DATA STRUCTURES

task:
{ objective: the invariant objective
  task: the task description
  status: SUCCESS FAILURE INCOMPLETE RETRIED
  output: ...
  subtasks: [task task ...]
}
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.collections [assoc])
(require hyrule.control [unless])
(import hyrule [inc])

(import functools [partial])
(import json)

(import guidance)
(import rich.tree [Tree])

(import .guides [model format-task manage-task divide-task revise-task attempt-task judge-task])
(import .utils [bots hash-id])


(defn debullet [markdown-list] ; -> list[str]
  "Just remove the bullet point bits from a markdown list and return items as a list."
  (lfor l (.split markdown-list "\n")
        (or (match (cut l 2)
                   "- " (cut l 2 None)
                   "* " (cut l 2 None))
            (match (cut l 4)
                   "[*] " (cut l 4 None)
                   "[ ] " (cut l 4 None))
            l)))

(defn indent [s [prefix "  "]]
  "Indent a string on each line with the prefix."
  (.join "\n"
         (map (fn [x] f"{prefix}{x}")
              (.split s "\n"))))

(defn short-id [x]
  (cut (hash-id x) 6))

(defn format-tree [task [i 0]]
  "Format the whole tree for human viewing."
  (let [label f"- {(:task task)} ({(:status task None)})"
        branch (or branch (Tree :label label))]
    (if (:subtasks task None)
        (for [t (:subtasks task)]
          (.add branch (format-tree t :branch branch))
          branch)
        branch)))
  
(defn finished? [task]
  "Is the task finished?"
  (in (:status task "INCOMPLETE") #("SUCCESS" "FAILURE" "REMOVED" "DIVIDED")))

(defn remove? [task]
  "Is the task marked for removal?"
  (= (:status task "INCOMPLETE") "REMOVED"))

(defn run [task]
  "Run to completion.")

(defn single-pass [task [all-tasks None]] ; -> task
  "Run all tasks once (recursively)"
  ; TODO: re-run gather if root task
  ; TODO: evaluate whole tree
  (assoc task "assigned" (:assigned task (get (bots) 0)))
  (assoc task "all_tasks" (or all-tasks (gather task)))
  (unless (:task task None)
    (assoc task "task" (:objective task)))
  (unless (:objective task None)
    (assoc task "objective" (:task task)))
  (assoc task "id" (:id task (short-id (:task task))))
  (if (:subtasks task None)
      {#** task
       "subtasks" (lfor t (:subtasks task)
                        :if (not (remove? t)) (single-pass t :all-tasks all-tasks))}
      (manage task)))

(defn gather [task [i 0]]
  "Condense the progress so far as context."
  (let [subtasks (:subtasks task None)
        g (fn [t] (gather t :i (inc i)))]
    (if subtasks
        (.join "\n" (map g subtasks))
        f"{(* "    " i)}#{(:id task None)} ({(:status task None)}): {(:task task None)}")))

(defn manage [task] ; -> task
  "Manage a task using the appropriate program. Leave completed tasks alone."
  (let [bot (:assigned task)]
    (if (finished? task)
        task
        (let [action (:result ((manage-task) :task task :llm (model bot))
                              None)]
          (print (:id task None) action (:task task None))
          (or (match action
                     "ACCEPT" {#** task
                               "status" "SUCCESS"}
                     "DIVIDE" (divide task)
                     "ATTEMPT" (attempt task)
                     "ESCALATE" (escalate task)
                     "REVISE" (revise task)
                     "RETRY" (retry task)
                     "REMOVE" {#** task
                               "status" "REMOVED"
                               "output" "Task was removed."}
                     "ABANDON" {#** task
                                "status" "FAILURE"
                                "output" "Task was abandoned."})
              (escalate task))))))

(defn escalate [task] ; -> task
  "Escalate a task to the next agent (in order)."
  ; we must flush the guidance cache otherwise it'll just escalate forever.
  (guidance.llms.OpenAI.cache.clear)
  (let [bot (:assigned task)
        bot-list (+ (bots) ["human" "god"])
        next-bot (get bot-list (inc (.index bot-list bot)))]
    ; TODO: we're failing human tasks directly, but could just ask for input.
    (if (= bot "human")
        {#** task
         "status" "FAILURE"}
        {#** task
         "assigned" next-bot
         "status" "INCOMPLETE"})))
  
(defn revise [task] ; -> task
  "Revise a task."
  (let [bot (:assigned task)
        new-task (:result ((revise-task) :task task :llm (model bot))
                          "task revision failed")]
    {#** task
     "task" new-task
     "status" "REVISED"
     "output" None}))
  
(defn divide [task] ; -> task
  "Divide a task into subtasks."
  (let [bot (:assigned task)
        subtasks (:result ((divide-task) :task task :llm (model bot))
                          "Failed to divide task.")]
    {#** task
     "status" "DIVIDED"
     "output" "Task was divided into subtasks."
     "subtasks" (lfor t (debullet subtasks)
                      {"objective" (:objective task)
                       "task" t
                       "id" (short-id t)
                       "status" "INCOMPLETE"})}))

(defn attempt [task] ; -> task
  "Attempt a task."
  (let [bot (:assigned task)
        output (:result ((attempt-task) :task task :llm (model bot))
                        None)]
    {#** task
     "output" output
     "status" "AWAITING DECISION"}))

(defn retry [task] ; -> task
  "Retry a task."
  (let [bot (:assigned task)
        output (:result ((retry-task) :task task :llm (model bot))
                        None)]
    {#** task
     "status" "RETRIED"
     "output" output}))
