defmodule Edenflowers.WeddingEnquiry do
  @moduledoc """
  A couple's enquiry from the weddings page. Nothing is stored: a valid
  enquiry is queued as an Oban job that emails the couple a copy, bcc Jennie,
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
    |> validate_number(:guests, greater_than: 0)
  end

  @doc """
  `selection` is the couple's picks from the price calculator, already
  rendered as lines in their language, and `estimate` the matching total.
  """
  def submit(params, selection, estimate, locale) do
    changeset = changeset(params)

    case apply_action(changeset, :insert) do
      # The honeypot field is hidden from people, so only bots fill it.
      # They're told it worked so they don't try again.
      {:ok, %{website: website}} when is_binary(website) ->
        :ok

      {:ok, enquiry} ->
        args =
          enquiry
          |> Map.take([:name, :email, :wedding_date, :venue, :guests, :message])
          |> Map.merge(%{selection: selection, estimate: estimate, locale: locale})

        with {:ok, _job} <- args |> SendEmails.new() |> Oban.insert(), do: :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
