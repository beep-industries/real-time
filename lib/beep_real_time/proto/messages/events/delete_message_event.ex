defmodule Messages.Events.DeleteMessageEvent do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:message_id, 1, type: :string)
end
