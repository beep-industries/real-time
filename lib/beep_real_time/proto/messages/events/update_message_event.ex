defmodule Messages.Events.UpdateMessageEvent do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:message_id, 1, type: :string)
  field(:content, 2, type: :string)
  field(:is_pinned, 3, type: :bool, proto3_optional: true)
  field(:notify_entries, 4, repeated: true, type: Messages.Events.NotifyEntry)
end
