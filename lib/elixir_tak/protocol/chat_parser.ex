defmodule ElixirTAK.Protocol.ChatParser do
  @moduledoc """
  Extracts structured chat fields from a CotEvent's raw_detail XML.

  Chat events (type `b-t-f`) carry sender, chatroom, and message body
  inside `<__chat>` and `<remarks>` elements within `<detail>`. This
  module parses those fields into a simple map for display and storage.
  """

  alias ElixirTAK.Protocol.CotEvent

  @type chat_message :: %{
          sender: String.t(),
          chatroom: String.t(),
          message: String.t(),
          sender_uid: String.t() | nil,
          time: DateTime.t() | nil,
          uid: String.t()
        }

  @doc """
  Parse a chat CotEvent into a structured chat message map.

  Returns `{:ok, chat_message}` or `:error` if the event is not a chat
  event or the raw_detail cannot be parsed.
  """
  @spec parse(%CotEvent{}) :: {:ok, chat_message()} | :error
  def parse(%CotEvent{type: "b-t-f" <> _, raw_detail: raw} = event) when is_binary(raw) do
    with {:ok, sender} <- extract_sender(raw),
         {:ok, chatroom} <- extract_chatroom(raw),
         {:ok, message} <- extract_message(raw) do
      {:ok,
       %{
         sender: sender,
         chatroom: chatroom,
         message: message,
         sender_uid: extract_sender_uid(raw),
         time: event.time,
         uid: event.uid
       }}
    end
  end

  def parse(_), do: :error

  @doc """
  Like `parse/1` but returns the map directly or nil.
  """
  @spec parse!(%CotEvent{}) :: chat_message() | nil
  def parse!(%CotEvent{} = event) do
    case parse(event) do
      {:ok, msg} -> msg
      :error -> nil
    end
  end

  @doc """
  Extract just the chatroom name from raw_detail XML.
  Returns the chatroom string or "unknown".
  """
  @spec extract_chatroom(String.t()) :: {:ok, String.t()} | :error
  def extract_chatroom(raw) when is_binary(raw) do
    case Regex.run(~r/chatroom="([^"]*)"/, raw) do
      [_, room] -> {:ok, room}
      nil -> :error
    end
  end

  # -- Private -----------------------------------------------------------------

  defp extract_sender(raw) do
    case Regex.run(~r/senderCallsign="([^"]*)"/, raw) do
      [_, sender] -> {:ok, sender}
      nil -> :error
    end
  end

  defp extract_message(raw) do
    case Regex.run(~r/<remarks[^>]*>([^<]*)<\/remarks>/, raw) do
      [_, body] -> {:ok, body}
      nil -> :error
    end
  end

  defp extract_sender_uid(raw) do
    case Regex.run(~r/<link\s+uid="([^"]*)"/, raw) do
      [_, uid] -> uid
      nil -> nil
    end
  end
end
