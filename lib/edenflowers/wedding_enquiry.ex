defmodule Edenflowers.WeddingEnquiry do
  @moduledoc """
  A couple's enquiry from the weddings page. Nothing is stored: a valid
  enquiry is queued as Oban jobs that email Jennie and acknowledge the couple,
  so a failed send is retried rather than lost.
  """

  import Ecto.Changeset

  alias Edenflowers.WeddingEnquiry.SendEmails

  @types %{
    name: :string,
    email: :string,
    wedding_date: :date,
    venue: :string,
    guests: :integer,
    message: :string,
    website: :string
  }

  def changeset(params) do
    {%{}, @types}
    |> cast(params, Map.keys(@types))
    |> validate_required([:name, :email, :wedding_date])
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/)
    |> validate_length(:message, max: 5000)
    |> validate_length(:name, max: 200)
    |> validate_length(:email, max: 200)
    |> validate_length(:venue, max: 200)
    |> validate_number(:guests, greater_than: 0)
  end

  @doc """
  `selection` is the couple's picks from the price calculator, already
  rendered as lines in their language, and `estimate` the matching total.
  """
  def submit(params, selection, estimate, locale, client_ip) do
    changeset = changeset(params)

    case apply_action(changeset, :insert) do
      # The honeypot field is hidden from people, so only bots fill it.
      # They're told it worked so they don't try again.
      {:ok, %{website: website}} when is_binary(website) ->
        :ok

      {:ok, enquiry} ->
        if rate_limited?(client_ip) do
          {:error, :rate_limited}
        else
          args =
            enquiry
            |> Map.take([:name, :email, :wedding_date, :venue, :guests, :message])
            |> Map.merge(%{selection: selection, estimate: estimate, locale: locale})

          acknowledgement = SendEmails.new(%{acknowledgement: true, email: enquiry.email, locale: locale})
          Oban.insert_all([SendEmails.new(args), acknowledgement])
          :ok
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Each enquiry also emails the typed address, so one visitor must not be able
  # to send it to many. No known address means no limit, as for sign-in.
  defp rate_limited?(nil), do: false

  defp rate_limited?(client_ip) do
    match?({:deny, _}, Edenflowers.RateLimiter.hit("wedding:ip:#{client_ip}", :timer.hours(1), 5))
  end
end
