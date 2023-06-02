"
Divide and conquer.

Implements a message protocol between agents.

Messages define a task tree with the objective as the root and atomic completable tasks as leaf nodes.

There shall be three message types, 

- task
- subtasks
- status

Their formats are defined in tasks.json

The manager should traverse the tree breadth-first.

manager: status -> update tree node
manager: subtasks -> branch tree, dispatch tasks

agent: status_request -> status
agent: task -> subtasks (can be empty)

manager SENDS:
    task
    status_request

agent SENDS:
    status
    subtasks


"
;;; --- *** AGENT'S TASK HANDLING NLP TEMPLATES *** ---

(defn manager [msg]
  "
Depth-first traversal of the tree.

status -> update the tree
subtasks -> dispatch tasks

If receiving bad subtasks or status, just don't update the tree and try again later.

  ")
  

(defn agent [msg]
  "
status_request -> status
task -> subtasks
  ")


;; message handling pipeline
(defn dispatch [])

(defn parse-msg [msg]
  "
- Get text reply
- extract json
- process content according to message type
  ")

(defn process-status [])

(defn process-task [])

(defn process-subtasks [])


;; agent:

;; agent 

