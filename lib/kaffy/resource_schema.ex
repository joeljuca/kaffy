defmodule Kaffy.ResourceSchema do
  @moduledoc false

  def primary_key(schema) do
    schema.__schema__(:primary_key)
  end

  def excluded_fields(schema) do
    {field, _, _} = schema.__schema__(:autogenerate_id)
    [field]
  end

  def fields(schema) do
    to_be_removed = fields_to_be_removed(schema)
    all_fields = get_all_fields(schema) -- to_be_removed
    reorder_fields(all_fields, schema)
  end

  defp get_all_fields(schema) do
    schema.__changeset__()
    |> Enum.map(fn {k, _} -> k end)
  end

  defp fields_to_be_removed(schema) do
    # if schema defines belongs_to assocations, remove the respective *_id fields.
    schema.__changeset__()
    |> Enum.reduce([], fn {field, type}, all ->
      case type do
        {:assoc, %Ecto.Association.BelongsTo{}} ->
          [field | all]

        {:assoc, %Ecto.Association.Has{cardinality: :many}} ->
          [field | all]

        {:assoc, %Ecto.Association.Has{cardinality: :one}} ->
          [field | all]

        _ ->
          all
      end
    end)
  end

  defp reorder_fields(fields_list, schema) do
    fields_list
    |> reorder_field(:name, :first)
    |> reorder_field(:title, :first)
    |> reorder_field(:id, :first)
    |> reorder_field(Kaffy.ResourceSchema.embeds(schema), :last)
    |> reorder_field([:inserted_at, :updated_at], :last)
  end

  defp reorder_field(fields_list, [], _), do: fields_list

  defp reorder_field(fields_list, [field | rest], position) do
    fields_list = reorder_field(fields_list, field, position)
    reorder_field(fields_list, rest, position)
  end

  defp reorder_field(fields_list, field, position) do
    if field in fields_list do
      fields_list = fields_list -- [field]

      case position do
        :first -> [field] ++ fields_list
        :last -> fields_list ++ [field]
      end
    else
      fields_list
    end
  end

  def has_field_filters?(resource) do
    admin_fields = Kaffy.ResourceAdmin.index(resource)

    fields_with_filters =
      Enum.map(admin_fields, fn f -> kaffy_field_filters(resource[:schema], f) end)

    Enum.any?(fields_with_filters, fn
      {_, filters} -> filters
      _ -> false
    end)
  end

  def kaffy_field_filters(_schema, {field, options}) do
    {field, Map.get(options || %{}, :filters, false)}
  end

  def kaffy_field_filters(_, _), do: false

  def kaffy_field_name(schema, {field, options}) do
    default_name = kaffy_field_name(schema, field)
    name = Map.get(options || %{}, :name)

    cond do
      is_binary(name) -> name
      is_function(name) -> name.(schema)
      true -> default_name
    end
  end

  def kaffy_field_name(_schema, field) when is_atom(field) do
    to_string(field) |> String.capitalize()
  end

  def kaffy_field_value(schema, {field, options}) do
    default_value = kaffy_field_value(schema, field)
    value = Map.get(options || %{}, :value)

    cond do
      is_map(value) && Map.has_key?(value, :__struct__) ->
        if value.__struct__ in [NaiveDateTime, DateTime, Date, Time] do
          value
        else
          Map.from_struct(value)
          |> Map.drop([:__meta__])
          |> Kaffy.Utils.json().encode!(escape: :html_safe, pretty: true)
        end

      is_binary(value) ->
        value

      is_function(value) ->
        value.(schema)

      is_map(value) ->
        Kaffy.Utils.json().encode!(value, escape: :html_safe, pretty: true)

      true ->
        default_value
    end
  end

  def kaffy_field_value(schema, field) when is_atom(field) do
    value = Map.get(schema, field, "")

    cond do
      is_map(value) && Map.has_key?(value, :__struct__) ->
        if value.__struct__ in [NaiveDateTime, DateTime, Date, Time] do
          value
        else
          Map.from_struct(value)
          |> Map.drop([:__meta__])
          |> Kaffy.Utils.json().encode!(escape: :html_safe, pretty: true)
        end

      is_map(value) ->
        Kaffy.Utils.json().encode!(value, escape: :html_safe, pretty: true)

      true ->
        value
    end
  end

  def display_string_fields([], all), do: Enum.reverse(all) |> Enum.join(",")

  def display_string_fields([{field, _} | rest], all) do
    display_string_fields(rest, [field | all])
  end

  def display_string_fields([field | rest], all) do
    display_string_fields(rest, [field | all])
  end

  def associations(schema) do
    schema.__schema__(:associations)
  end

  def association(schema, name) do
    schema.__schema__(:association, name)
  end

  def association_schema(schema, assoc) do
    association(schema, assoc).queryable
  end

  def embeds(schema) do
    schema.__schema__(:embeds)
  end

  def embed(schema, name) do
    schema.__schema__(:embed, name)
  end

  def embed_struct(schema, name) do
    embed(schema, name).related
  end

  def search_fields(resource) do
    schema = resource[:schema]
    Enum.filter(fields(schema), fn f -> field_type(schema, f) == :string end)
  end

  def filter_fields(_), do: nil

  def field_type(_schema, {_, type}), do: type
  def field_type(schema, field), do: schema.__schema__(:type, field)

  def get_map_fields(schema) do
    get_all_fields(schema)
    |> Enum.filter(fn f -> field_type(schema, f) == :map end)
  end

  def widgets(_resource) do
    []
  end
end
