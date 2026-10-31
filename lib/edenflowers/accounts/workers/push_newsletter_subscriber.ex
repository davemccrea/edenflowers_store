defmodule Edenflowers.Accounts.Workers.PushNewsletterSubscriber do
  @moduledoc """
  Sends one user's newsletter opt-in to MailerLite as soon as it changes on
  the site: opted in makes them an active subscriber (lifting an older
  unsubscribe), opted out marks them unsubscribed. It reads the user when it
  runs, so it always sends their latest choice.

  Runs in the single-file newsletter queue with `SyncNewsletterList`.
  """

  use Oban.Worker, queue: :newsletter, max_attempts: 10

  require Ash.Query

  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.MailerLite
  alias Edenflowers.Accounts.User

  def enqueue(user) do
    %{"email" => to_string(user.email)} |> new() |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"email" => email}}) do
    if MailerLite.configured?(), do: push(email), else: :ok
  end

  defp push(email) do
    query = Ash.Query.filter(User, email == ^email)

    case Accounts.list_newsletter_subscribers!(query: query, actor: system_actor()) do
      [user] -> MailerLite.subscribe(user)
      [] -> MailerLite.unsubscribe(email)
    end
  end
end
