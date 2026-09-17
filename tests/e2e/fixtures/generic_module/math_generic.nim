proc square*[T](x: T): T =
  ## Squares an element of type T
  result = x * x

type
  Box*[T] = object
    item*: T

let sqInt = square(5)
let sqFloat = square(3.14)
