type status = Pending | Completed

let status queue (receipt : Backend.receipt) =
  Result.map
    (function true -> Completed | false -> Pending)
    (Backend.poll_through queue receipt.epoch)

let completed_epoch = Backend.completed_epoch
