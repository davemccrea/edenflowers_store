defmodule Edenflowers.Accounts.Workers.SyncNewsletterList do
  @moduledoc """
  Nightly reconciliation of MailerLite's Newsletter group with the site's
  newsletter opt-ins. Opt-in changes reach MailerLite straight away through
  `PushNewsletterSubscriber`; this catches what that can't:

    * Subscribers who unsubscribed in MailerLite are opted out on the site.
      A newer opt-in on the site would already have resubscribed them, so an
      unsubscribe seen here is always the latest word.
    * Active Newsletter members the site doesn't have as opted in (a push
      that ran out of retries, a contact added to the group by hand) are
      taken out of the group. Their status and other groups stay, so contacts
      Jennie keeps outside the newsletter are never touched.
    * Everyone else gets their fields refreshed and is put back in the group
      if they're missing from it.

  Customers who never opted in are not sent to MailerLite at all (privacy
  policy).

  Runs in the single-file newsletter queue with `PushNewsletterSubscriber`,
  so an opt-in can't land between this reading MailerLite and acting on it.
  """

  use Oban.Worker, queue: :newsletter, max_attempts: 3, unique: [period: 3600]

  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.MailerLite

  @impl true
  def perform(_job) do
    if MailerLite.configured?(), do: sync(), else: :ok
  end

  defp sync do
    with {:ok, members} <- MailerLite.newsletter_members(),
         {:ok, unsubscribed} <- MailerLite.list("unsubscribed") do
      unsubscribed = MapSet.new(unsubscribed)
      users = Accounts.list_newsletter_subscribers!(actor: system_actor())

      {left, subscribers} = Enum.split_with(users, &(normalize(&1.email) in unsubscribed))
      Enum.each(left, &Accounts.update_newsletter_preference!(&1, false, &1.locale, actor: system_actor()))

      stray = Map.drop(members, Enum.map(subscribers, &normalize(&1.email)))

      with :ok <- each(Map.values(stray), &MailerLite.remove_from_newsletter/1) do
        each(subscribers, &MailerLite.update_fields/1)
      end
    end
  end

  # ponytail: one request per subscriber nightly, move to MailerLite's batch
  # endpoint if the list outgrows 120 requests a minute.
  defp each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize(email), do: email |> to_string() |> String.downcase()
end
