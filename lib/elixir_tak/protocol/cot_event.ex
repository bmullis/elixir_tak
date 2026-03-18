defmodule ElixirTAK.Protocol.CotEvent do
  @moduledoc "Structured representation of a Cursor-on-Target event."

  @type t :: %__MODULE__{
          uid: String.t(),
          type: String.t(),
          how: String.t() | nil,
          time: DateTime.t() | nil,
          start: DateTime.t() | nil,
          stale: DateTime.t() | nil,
          point: map() | nil,
          detail: map() | nil,
          raw_detail: String.t() | nil
        }

  @enforce_keys [:uid, :type, :point]
  defstruct [:uid, :type, :how, :time, :start, :stale, :point, :detail, :raw_detail]

  @doc """
  Classify the CoT type into a friendly category.
  """
  def affiliation(%__MODULE__{type: "a-f-" <> _}), do: :friendly
  def affiliation(%__MODULE__{type: "a-h-" <> _}), do: :hostile
  def affiliation(%__MODULE__{type: "a-n-" <> _}), do: :neutral
  def affiliation(%__MODULE__{type: "a-u-" <> _}), do: :unknown
  def affiliation(%__MODULE__{}), do: :unknown

  def stale?(%__MODULE__{stale: nil}), do: false

  def stale?(%__MODULE__{stale: stale}) do
    DateTime.compare(stale, DateTime.utc_now()) == :lt
  end

  def chat?(%__MODULE__{type: "b-t-f" <> _}), do: true
  def chat?(%__MODULE__{}), do: false
end
