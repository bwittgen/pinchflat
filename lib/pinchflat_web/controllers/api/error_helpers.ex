defmodule PinchflatWeb.Api.ErrorHelpers do
  @moduledoc """
  Shared helpers for formatting API error responses.
  """

  @doc """
  Traverses changeset errors and formats them as a map of field names to error message lists.
  """
  def format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
