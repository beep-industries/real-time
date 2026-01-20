defmodule Messages.Events.CreateMessageEvent do
  @moduledoc false
  use Protobuf, syntax: :proto3

  defmodule Attachment do
    @moduledoc false
    use Protobuf, syntax: :proto3

    field(:id, 1, type: :string)
    field(:name, 2, type: :string)
    field(:url, 3, type: :string)
  end

  field(:message_id, 1, type: :string)
  field(:channel_id, 2, type: :string)
  field(:author_id, 3, type: :string)
  field(:content, 4, type: :string)
  field(:reply_to_message_id, 5, type: :string)
  field(:attachments, 6, repeated: true, type: Attachment)
  field(:notify_entries, 7, repeated: true, type: Messages.Events.NotifyEntry)
end
