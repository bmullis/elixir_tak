defmodule ElixirTAK.History.EventRecord do
  @moduledoc "Ecto schema for persisted CoT events."

  use Ecto.Schema
  import Ecto.Changeset

  alias ElixirTAK.Protocol.{CotEvent, CotParser}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "events" do
    field(:uid, :string)
    field(:type, :string)
    field(:how, :string)
    field(:callsign, :string)
    field(:group_name, :string)
    field(:lat, :float)
    field(:lon, :float)
    field(:hae, :float)
    field(:speed, :float)
    field(:course, :float)
    field(:raw_xml, :string)
    field(:event_time, :utc_datetime_usec)
    field(:stale_time, :utc_datetime_usec)
    field(:source_server, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @cast_fields [
    :uid,
    :type,
    :how,
    :callsign,
    :group_name,
    :lat,
    :lon,
    :hae,
    :speed,
    :course,
    :raw_xml,
    :event_time,
    :stale_time,
    :source_server
  ]

  @doc "Build a changeset for an event record."
  def changeset(record, attrs) do
    record
    |> cast(attrs, @cast_fields)
    |> validate_required([:uid, :type, :event_time])
  end

  @doc "Convert an EventRecord back to a CotEvent struct."
  def to_cot_event(%__MODULE__{raw_xml: raw_xml} = record) when is_binary(raw_xml) do
    case CotParser.parse(raw_xml) do
      {:ok, event} -> event
      {:error, _} -> from_fields(record)
    end
  end

  def to_cot_event(%__MODULE__{} = record), do: from_fields(record)

  defp from_fields(record) do
    %CotEvent{
      uid: record.uid,
      type: record.type,
      how: record.how,
      time: record.event_time,
      start: record.event_time,
      stale: record.stale_time,
      point: %{lat: record.lat, lon: record.lon, hae: record.hae, ce: nil, le: nil},
      detail: %{
        callsign: record.callsign,
        group: if(record.group_name, do: %{name: record.group_name, role: nil}, else: nil),
        track: %{speed: record.speed, course: record.course}
      },
      raw_detail: nil
    }
  end

  @doc "Extract a flat map from a CotEvent for insert_all."
  def from_cot_event(%CotEvent{} = event, raw_xml, group, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    %{
      id: Ecto.UUID.generate(),
      uid: event.uid,
      type: event.type,
      how: event.how,
      callsign: get_callsign(event),
      group_name: group,
      lat: event.point && event.point.lat,
      lon: event.point && event.point.lon,
      hae: event.point && event.point.hae,
      speed: get_speed(event),
      course: get_course(event),
      raw_xml: raw_xml,
      event_time: to_usec(event.time) || now,
      stale_time: to_usec(event.stale),
      source_server: Keyword.get(opts, :source_server),
      inserted_at: now,
      updated_at: now
    }
  end

  defp to_usec(%DateTime{microsecond: {us, _}} = dt), do: %{dt | microsecond: {us, 6}}
  defp to_usec(nil), do: nil

  defp get_callsign(%{detail: %{callsign: cs}}) when is_binary(cs), do: cs
  defp get_callsign(_), do: nil

  defp get_speed(%{detail: %{track: %{speed: s}}}) when is_number(s), do: s
  defp get_speed(_), do: nil

  defp get_course(%{detail: %{track: %{course: c}}}) when is_number(c), do: c
  defp get_course(_), do: nil
end
