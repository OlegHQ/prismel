let next = Atomic.make 0

let fresh () = Atomic.fetch_and_add next 1
