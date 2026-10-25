defmodule Edenflowers.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :edenflowers

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
          check_course_registration_states!(repo)
        end)
    end
  end

  def check_course_registration_states!(repo) do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(repo, "SELECT count(*) FROM course_registrations WHERE status = 'awaiting_payment'")

    if count > 0 do
      raise "Deployment blocked: #{count} course registrations still have status awaiting_payment. " <>
              "Back up production, resolve their payments and cancel them using the previous release before deploying."
    end

    :ok
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
