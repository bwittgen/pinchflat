defmodule Pinchflat.Repo.Migrations.AddPlexSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :plex_server_url, :string
      add :plex_token, :string
    end
  end
end
