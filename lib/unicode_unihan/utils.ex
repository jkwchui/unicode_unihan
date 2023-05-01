defmodule Unicode.Unihan.Utils do
  @moduledoc """
  Functions to parse the Unicode Unihand database
  files.

  """
  for file <- Path.wildcard(Path.join(__DIR__, "../../data/**/**")) do
    @external_resource file
  end

  @doc false
  @data_dir Path.join(__DIR__, "../../data") |> Path.expand()
  def data_dir do
    @data_dir
  end

  @doc """
  Parse all Unicode Unihan files and return
  a mapping from codepoint to a map of metadata
  for that codepoint.

  """
  @subdir "unihan"
  def parse_files do
    @data_dir
    |> Path.join(@subdir)
    |> File.ls!()
    |> Enum.reduce(%{}, &parse_file(&1, &2))
  end

  @doc """
  Parse one Unicode Unihan file and return
  a mapping from codepoint to a map of metadata
  for that codepoint.

  """
  def parse_file(file, map \\ %{}) do
    path = Path.join(@data_dir, [@subdir, "/", file])
    fields = unihan_fields()

    Enum.reduce(File.stream!(path), map, fn line, map ->
      case line do
        <<"#", _rest::bitstring>> ->
          map

        <<"\n", _rest::bitstring>> ->
          map

        data ->
          [codepoint, key, value] =
            data
            |> String.split("\t")
            |> Enum.map(&String.trim/1)

          codepoint = decode_codepoint(codepoint)

          Map.get_and_update(map, codepoint, fn
            nil ->
              {key, value} = decode_metadata(key, value, fields)
              {nil, %{key => value, :codepoint => codepoint}}

            current_value when is_map(current_value) ->
              {key, value} = decode_metadata(key, value, fields)
              {current_value, Map.put(current_value, key, value)}
          end)
          |> elem(1)
      end
    end)
  end

  @doc """
  Returns a map of the field definitions for a
  Unihan codepoint.

  """
  def unihan_fields do
    @data_dir
    |> Path.join("unihan_fields.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("records")
    |> Enum.map(fn map ->
      fields = Map.get(map, "fields")
      {name, fields} = Map.pop(fields, "name")

      fields =
        Enum.map(fields, fn
          {"Status", status} ->
            {:status, normalize_atom(status)}

          {"delimiter", "space"} ->
            {:delimiter, "\s"}

          {"delimiter", "N/A"} ->
            {:delimiter, nil}

          {"category", category} ->
            {:category, normalize_atom(category)}

          {"syntax", syntax} when is_binary(syntax) ->
            {:syntax, Regex.compile!(syntax, [:unicode])}

          {field, value} ->
            {String.to_atom(field), value}
        end)
        |> Map.new()

      {String.to_atom(name), fields}
    end)
    |> Map.new()
  end

  defp decode_metadata(key, value, fields) do
    key = String.to_atom(key)

    value =
      key
      |> maybe_split_value(value, fields)
      |> decode_value(key, fields)

    {key, value}
  end

  defp maybe_split_value(key, value, fields) do
    field = Map.fetch!(fields, key)

    case field.delimiter do
      nil -> value
      delimiter -> String.split(value, delimiter)
    end
  end

  # Values where decoding depends on the number of items
  # in the value list go here - before the clause
  # that maps over a list of values individually.

  defp decode_value(value, :kTotalStrokes, _fields) do
    case Enum.map(value, &String.to_integer/1) do
      [zh] -> %{"zh-Hans": zh, "zh-Hant": zh}
      [hans, hant] -> %{"zh-Hans": hans, "zh-Hant": hant}
    end
  end

  # When its a list, map each value to decode it.
  # Most decode_value clauses should go below this one.

  defp decode_value(value, key, fields) when is_list(value) do
    Enum.map(value, &decode_value(&1, key, fields))
  end

  defp decode_value(value, :kTraditionalVariant, _fields) do
    decode_codepoint(value)
  end

  defp decode_value(value, :kSimplifiedVariant, _fields) do
    decode_codepoint(value)
  end

  defp decode_value(value, :kHangul, _fields) do
    case String.split(value, ":", trim: true) do
      [grapheme] -> %{grapheme: grapheme, source: nil}
      [grapheme, source] -> %{grapheme: grapheme, source: source}
    end
  end

  # The default decoding is to do nothing.

  defp decode_value(value, _key, _fields) do
    value
  end

  # Decodes a standard `U+xxxx` codepoing into
  # its integer form.

  defp decode_codepoint("U+" <> codepoint) do
    String.to_integer(codepoint, 16)
  end

  defp normalize_atom(category) do
    category
    |> String.downcase()
    |> String.replace(" ", "_")
    |> String.to_atom()
  end
end
