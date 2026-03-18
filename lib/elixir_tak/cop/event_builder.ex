defmodule ElixirTAK.COP.EventBuilder do
  @moduledoc """
  Builds CoT events originating from the dashboard/COP.

  All functions return `%CotEvent{}` structs with properly formatted `raw_detail`
  XML that round-trips through `CotParser.parse/1`. Events use `how="h-g-i-g-o"`
  (human, GPS-derived, inferred, ground, operational) and UIDs prefixed with `COP-`.

  Identity fields (callsign, group, role) are sourced from `COP.Identity` by
  default but can be overridden via opts.
  """

  alias ElixirTAK.COP.Identity
  alias ElixirTAK.Protocol.CotEvent

  @how "h-g-i-g-o"

  @doc """
  Build a base CotEvent with common fields populated.

  ## Options

    * `:uid` - override the generated UID (default: `"COP-" <> uuid4()`)
    * `:callsign` - override `Identity.callsign/0`
    * `:group` - override `Identity.group/0`
    * `:role` - override `Identity.role/0`
    * `:stale_minutes` - minutes until stale (default: 15)
    * `:time` - override event time (default: `DateTime.utc_now/0`)
    * `:raw_detail` - pre-built detail XML string

  """
  @spec build_base_event(String.t(), map(), keyword()) :: CotEvent.t()
  def build_base_event(type, point, opts \\ []) do
    now = opts[:time] || DateTime.utc_now()
    stale = stale_time(opts[:stale_minutes] || 15, now)
    uid = opts[:uid] || "COP-#{uuid4()}"
    callsign = opts[:callsign] || Identity.callsign()
    group_name = opts[:group] || Identity.group()
    role = opts[:role] || Identity.role()

    %CotEvent{
      uid: uid,
      type: type,
      how: @how,
      time: now,
      start: now,
      stale: stale,
      point: normalize_point(point),
      detail: %{
        callsign: callsign,
        group: %{name: group_name, role: role},
        track: nil
      },
      raw_detail: opts[:raw_detail]
    }
  end

  @doc """
  Build a marker/point event (type `b-m-p-s-p-i`, spot point).

  ## Options

  All `build_base_event/3` options plus:

    * `:remarks` - optional text annotation
    * `:stale_minutes` - defaults to 1440 (24 hours) for markers

  """
  @spec build_marker(float(), float(), String.t(), keyword()) :: CotEvent.t()
  def build_marker(lat, lon, name, opts \\ []) do
    opts = Keyword.put_new(opts, :stale_minutes, 1440)
    callsign = opts[:callsign] || Identity.callsign()
    group_name = opts[:group] || Identity.group()
    role = opts[:role] || Identity.role()
    remarks = opts[:remarks]

    detail_xml =
      [
        "<detail>",
        "<contact callsign=\"#{xml_escape(name)}\"/>",
        "<__group name=\"#{xml_escape(group_name)}\" role=\"#{xml_escape(role)}\"/>",
        if(remarks, do: "<remarks>#{xml_escape(remarks)}</remarks>", else: ""),
        "<link uid=\"#{xml_escape(callsign)}\" relation=\"p-p\" type=\"a-f-G\"/>",
        "</detail>"
      ]
      |> IO.iodata_to_binary()

    point = %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil}
    build_base_event("b-m-p-s-p-i", point, Keyword.put(opts, :raw_detail, detail_xml))
  end

  @doc """
  Build a chat message event (type `b-t-f`).

  Chat UIDs follow the ATAK convention: `GeoChat.<sender_uid>.<chatroom>.<uuid>`.
  The point is set to 0,0 as chat messages have no position.

  ## Options

  All `build_base_event/3` options plus:

    * `:sender_uid` - override `Identity.uid/0`

  """
  @spec build_chat(String.t(), String.t(), keyword()) :: CotEvent.t()
  def build_chat(message, chatroom \\ "All Chat Rooms", opts \\ []) do
    sender_uid = opts[:sender_uid] || Identity.uid()
    callsign = opts[:callsign] || Identity.callsign()
    now = opts[:time] || DateTime.utc_now()
    time_str = DateTime.to_iso8601(now)
    chat_uid = "GeoChat.#{sender_uid}.#{chatroom}.#{uuid4()}"

    detail_xml =
      [
        "<detail>",
        "<__chat chatroom=\"#{xml_escape(chatroom)}\" id=\"#{xml_escape(chatroom)}\" senderCallsign=\"#{xml_escape(callsign)}\">",
        "<chatgrp uid0=\"#{xml_escape(sender_uid)}\" uid1=\"#{xml_escape(chatroom)}\" id=\"#{xml_escape(chatroom)}\"/>",
        "</__chat>",
        "<remarks source=\"BAO.F.ATAK.#{xml_escape(sender_uid)}\" time=\"#{time_str}\" to=\"#{xml_escape(chatroom)}\">#{xml_escape(message)}</remarks>",
        "<link uid=\"#{xml_escape(sender_uid)}\" relation=\"p-p\" type=\"a-f-G-U-C\"/>",
        "</detail>"
      ]
      |> IO.iodata_to_binary()

    point = %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil}

    build_base_event(
      "b-t-f",
      point,
      opts
      |> Keyword.put(:raw_detail, detail_xml)
      |> Keyword.put(:uid, chat_uid)
      |> Keyword.put(:time, now)
      |> Keyword.put_new(:stale_minutes, 1440)
    )
  end

  @doc """
  Build a shape/drawing event (type `u-d-f`, freeform polygon).

  Vertices are `[{lat, lon}, ...]` tuples. The event point is the centroid.

  ## Options

  All `build_base_event/3` options plus:

    * `:stroke_color` - ARGB integer (default: -1, white)
    * `:fill_color` - ARGB integer (default: 1_291_845_632, semi-transparent cyan)
    * `:remarks` - optional text annotation

  """
  @spec build_shape([{float(), float()}], String.t(), keyword()) :: CotEvent.t()
  def build_shape(vertices, name, opts \\ []) when length(vertices) >= 3 do
    opts = Keyword.put_new(opts, :stale_minutes, 1440)
    group_name = opts[:group] || Identity.group()
    role = opts[:role] || Identity.role()
    stroke_color = opts[:stroke_color] || -1
    fill_color = opts[:fill_color] || 1_291_845_632
    remarks = opts[:remarks]

    link_points =
      vertices
      |> Enum.map(fn {lat, lon} ->
        "<link point=\"#{lat},#{lon},0.0\" />"
      end)
      |> Enum.join()

    detail_xml =
      [
        "<detail>",
        "<contact callsign=\"#{xml_escape(name)}\"/>",
        "<__group name=\"#{xml_escape(group_name)}\" role=\"#{xml_escape(role)}\"/>",
        "<strokeColor value=\"#{stroke_color}\"/>",
        "<fillColor value=\"#{fill_color}\"/>",
        link_points,
        if(remarks, do: "<remarks>#{xml_escape(remarks)}</remarks>", else: ""),
        "</detail>"
      ]
      |> IO.iodata_to_binary()

    centroid = compute_centroid(vertices)
    build_base_event("u-d-f", centroid, Keyword.put(opts, :raw_detail, detail_xml))
  end

  @doc """
  Build a route event (type `b-m-r`).

  Waypoints are `[{lat, lon}, ...]` tuples. The event point is the first waypoint.
  Route waypoints are encoded as `<link>` elements with `relation="c"`.

  ## Options

  All `build_base_event/3` options plus:

    * `:stroke_color` - ARGB integer (default: -1, white)
    * `:remarks` - optional text annotation

  """
  @spec build_route([{float(), float()}], String.t(), keyword()) :: CotEvent.t()
  def build_route(waypoints, name, opts \\ []) when length(waypoints) >= 2 do
    opts = Keyword.put_new(opts, :stale_minutes, 1440)
    group_name = opts[:group] || Identity.group()
    role = opts[:role] || Identity.role()
    stroke_color = opts[:stroke_color] || -1
    remarks = opts[:remarks]

    link_waypoints =
      waypoints
      |> Enum.map(fn {lat, lon} ->
        "<link point=\"#{lat},#{lon},0.0\" relation=\"c\" />"
      end)
      |> Enum.join()

    detail_xml =
      [
        "<detail>",
        "<contact callsign=\"#{xml_escape(name)}\"/>",
        "<__group name=\"#{xml_escape(group_name)}\" role=\"#{xml_escape(role)}\"/>",
        "<strokeColor value=\"#{stroke_color}\"/>",
        link_waypoints,
        if(remarks, do: "<remarks>#{xml_escape(remarks)}</remarks>", else: ""),
        "</detail>"
      ]
      |> IO.iodata_to_binary()

    {lat, lon} = hd(waypoints)
    point = %{lat: lat, lon: lon, hae: nil, ce: nil, le: nil}
    build_base_event("b-m-r", point, Keyword.put(opts, :raw_detail, detail_xml))
  end

  @doc """
  Build a delete event (type `t-x-d-d`) to remove a previously sent object.

  The target UID identifies the entity to delete. The event point is 0,0.
  """
  @spec build_delete(String.t(), keyword()) :: CotEvent.t()
  def build_delete(target_uid, opts \\ []) do
    opts = Keyword.put_new(opts, :stale_minutes, 5)

    detail_xml =
      "<detail><link uid=\"#{xml_escape(target_uid)}\" relation=\"none\" type=\"none\"/></detail>"

    point = %{lat: 0.0, lon: 0.0, hae: nil, ce: nil, le: nil}
    build_base_event("t-x-d-d", point, Keyword.put(opts, :raw_detail, detail_xml))
  end

  @doc """
  Build a circle shape event (type `u-d-c-c`).

  The event point is the center. Radius is in meters. A ring of vertices is
  generated on the circumference for clients that render circles as polygons.

  ## Options

  All `build_base_event/3` options plus:

    * `:stroke_color` - ARGB integer (default: -1, white)
    * `:fill_color` - ARGB integer (default: 1_291_845_632, semi-transparent cyan)
    * `:remarks` - optional text annotation

  """
  @spec build_circle(float(), float(), float(), String.t(), keyword()) :: CotEvent.t()
  def build_circle(center_lat, center_lon, radius_m, name, opts \\ [])
      when is_number(radius_m) and radius_m > 0 do
    opts = Keyword.put_new(opts, :stale_minutes, 1440)
    group_name = opts[:group] || Identity.group()
    role = opts[:role] || Identity.role()
    stroke_color = opts[:stroke_color] || -1
    fill_color = opts[:fill_color] || 1_291_845_632
    remarks = opts[:remarks]

    # Generate circumference vertices for clients that render via polygon
    vertices = circle_vertices(center_lat, center_lon, radius_m, 36)

    link_points =
      vertices
      |> Enum.map(fn {lat, lon} -> "<link point=\"#{lat},#{lon},0.0\" />" end)
      |> Enum.join()

    detail_xml =
      [
        "<detail>",
        "<contact callsign=\"#{xml_escape(name)}\"/>",
        "<__group name=\"#{xml_escape(group_name)}\" role=\"#{xml_escape(role)}\"/>",
        "<strokeColor value=\"#{stroke_color}\"/>",
        "<fillColor value=\"#{fill_color}\"/>",
        "<Shape ellipseMajor=\"#{format_float(radius_m)}\" ellipseMinor=\"#{format_float(radius_m)}\"/>",
        link_points,
        if(remarks, do: "<remarks>#{xml_escape(remarks)}</remarks>", else: ""),
        "</detail>"
      ]
      |> IO.iodata_to_binary()

    point = %{lat: center_lat, lon: center_lon, hae: nil, ce: nil, le: nil}
    build_base_event("u-d-c-c", point, Keyword.put(opts, :raw_detail, detail_xml))
  end

  @doc """
  Convert a CSS hex color string to a TAK signed ARGB 32-bit integer.

  Accepts `"#RRGGBB"` (alpha defaults to 0xFF) or `"#AARRGGBB"`.
  Returns the signed 32-bit integer TAK uses for strokeColor/fillColor.

  ## Examples

      iex> EventBuilder.css_to_argb("#FFFFFF")
      -1

      iex> EventBuilder.css_to_argb("#FF00BCD4")
      -16728876

  """
  @spec css_to_argb(String.t()) :: integer()
  def css_to_argb("#" <> hex) when byte_size(hex) == 6 do
    {rgb, ""} = Integer.parse(hex, 16)
    unsigned = Bitwise.bor(0xFF000000, rgb)
    to_signed_int32(unsigned)
  end

  def css_to_argb("#" <> hex) when byte_size(hex) == 8 do
    {unsigned, ""} = Integer.parse(hex, 16)
    to_signed_int32(unsigned)
  end

  @doc """
  Compute a stale DateTime `minutes` from now (or from a given base time).
  """
  @spec stale_time(pos_integer(), DateTime.t()) :: DateTime.t()
  def stale_time(minutes \\ 15, base \\ DateTime.utc_now()) do
    DateTime.add(base, minutes * 60, :second)
  end

  # -- Private -----------------------------------------------------------------

  defp normalize_point(%{lat: _, lon: _} = p) do
    %{
      lat: p.lat,
      lon: p.lon,
      hae: Map.get(p, :hae),
      ce: Map.get(p, :ce),
      le: Map.get(p, :le)
    }
  end

  defp compute_centroid(vertices) do
    count = length(vertices)

    {sum_lat, sum_lon} =
      Enum.reduce(vertices, {0.0, 0.0}, fn {lat, lon}, {al, ol} -> {al + lat, ol + lon} end)

    %{lat: sum_lat / count, lon: sum_lon / count, hae: nil, ce: nil, le: nil}
  end

  defp xml_escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp xml_escape(val), do: xml_escape(to_string(val))

  defp format_float(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 1)
  defp format_float(i) when is_integer(i), do: :erlang.float_to_binary(i / 1, decimals: 1)

  defp to_signed_int32(unsigned) when unsigned > 0x7FFFFFFF do
    unsigned - 0x100000000
  end

  defp to_signed_int32(unsigned), do: unsigned

  @earth_radius_m 6_371_000.0

  defp circle_vertices(center_lat, center_lon, radius_m, n) do
    clat = center_lat * :math.pi() / 180.0
    clon = center_lon * :math.pi() / 180.0
    angular_dist = radius_m / @earth_radius_m

    for i <- 0..(n - 1) do
      bearing = 2 * :math.pi() * i / n

      lat =
        :math.asin(
          :math.sin(clat) * :math.cos(angular_dist) +
            :math.cos(clat) * :math.sin(angular_dist) * :math.cos(bearing)
        )

      lon =
        clon +
          :math.atan2(
            :math.sin(bearing) * :math.sin(angular_dist) * :math.cos(clat),
            :math.cos(angular_dist) - :math.sin(clat) * :math.sin(lat)
          )

      {Float.round(lat * 180.0 / :math.pi(), 7), Float.round(lon * 180.0 / :math.pi(), 7)}
    end
  end

  defp uuid4 do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      <<g1::binary-size(8), g2::binary-size(4), g3::binary-size(4), g4::binary-size(4),
        g5::binary-size(12)>> = hex

      "#{g1}-#{g2}-#{g3}-#{g4}-#{g5}"
    end)
  end
end
