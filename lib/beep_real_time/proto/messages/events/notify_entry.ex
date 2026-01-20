defmodule Messages.Events.NotifyEntry do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:type, 1, type: :string)
  field(:id, 2, type: :string)
end
