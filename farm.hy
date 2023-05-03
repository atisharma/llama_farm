"
Works fairly well with llama-supercot.

Here we model the executive function of the brain by using a community (farm) of AIs.
Each area of executive function will have an AI specialised in its function. These are each one of the 'voices' of the collective AI.

We implement the following voices:
    - director (attentional control)
    - judge (inhibitory control)
    - resource controller
    - planner (cognitive flexibility)
    - recall (working memory)
    - summariser (cognitive inhibition)
    - researcher (access data / www)
    - innovator (the creative voice)

The basic areas of executive function are:

Attentional control:
    This involves an individual's ability to focus attention and concentrate on something specific in the environment (or, here, on a task). This is covered by prioritisation.

Cognitive flexibility:
    Sometimes referred to as mental flexibility, this refers to the ability to switch from one mental task to another or to think about multiple things at the same time. This is an architectural choice that queues and prioritises tasks.

Cognitive inhibition:
    This involves the ability to tune out irrelevant information. We implement this using a summary function.

Inhibitory control:
    This involves the ability to inhibit impulses or desires in order to engage in more appropriate or beneficial behaviors. We implement this by reviewing the alignment of activity with the task and underlying values.

Working memory:
    Working memory is a “temporary storage system” in the brain that holds several facts or thoughts in mind while solving a problem or performing a task.


Ways to Improve Your Executive Function

* Break up large tasks into independent small steps.
* Create checklists for things you need to do.
* Give yourself time to transition between activities.
* Make a schedule to help you stay on track.
* Use a calendar to help you remember and plan for long-term activities, tasks, and goals.
* Use visual aids to help you process and understand information.
* Write down due dates or important deadlines and put them in a visible location.


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

"

(import agents [Personality])


(setv base-url "http://jupiter.letterbox.pw:5001/v1")


(setv director (Personality :base-url base-url
                            :character "I review and revise the aims, removing and adding tasks as needed."
                            :params {"temperature" 0.5
                                     "repetition_penalty" 1.1
                                     "max_tokens" 2000
                                     "model" "default"}))

(setv innovator (Personality :base-url base-url
                             :character "I give one new approach for reaching the objective."
                             :params {"temperature" 0.9
                                      "repetition_penalty" 1.1
                                      "max_tokens" 2000
                                      "model" "default"}))


(defn extract []
  "Extract some section of a reply.")
; fancy regexp goes here

(defn extract-action []
  "The current action, from a reply.")
; fancy regexp goes here

