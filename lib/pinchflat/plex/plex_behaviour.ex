defmodule Pinchflat.Plex.PlexBehaviour do
  @moduledoc """
  This module defines the behaviour for the Plex API client.
  Allows mocking in tests.
  """

  alias Pinchflat.Media.MediaItem

  @callback enabled?() :: boolean()
  @callback trigger_library_scan(String.t() | nil) :: :ok | {:error, String.t()}
  @callback find_media_item(%MediaItem{}) :: {:ok, map()} | {:error, String.t()}
  @callback check_metadata(%MediaItem{}, map()) :: {:ok, [map()]} | {:error, String.t()}
  @callback sync_watch_status(%MediaItem{}, map()) :: {:ok, map()} | {:error, String.t()}
end
