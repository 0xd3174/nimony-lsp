proc add*(a, b: int): int =
  ## Adds two integers
  result = a + b

proc formatUser*(name: string): string =
  ## Formats username
  result = "[" & name & "]"
