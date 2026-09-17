import utils

type
  User* = object
    id*: int
    name*: string

proc greet*(u: User): string =
  ## Returns personalized greeting for user
  result = "Hello, " & u.name & "!"

let admin = User(id: 1, name: "Admin")
let msg = greet(admin)
let total = add(10, 20)
