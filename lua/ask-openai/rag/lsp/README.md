## TODOs / Ideas

### Prompt based

```py

# PRN try using InstructorEmbedding to include a prompt with the query!
#   guides the encoding... like a system prompt... obviously requires different models than direct embedding
#   also need to use on the document embedding side too, with consistent instruction (prompt)
from InstructorEmbedding import INSTRUCTOR
# hkunlp/instructor-large|base|xl
model = INSTRUCTOR("hkunlp/instructor-large")
sentence = "Represent this sentence for retrieval"
embedding = model.encode([[sentence]])

```
