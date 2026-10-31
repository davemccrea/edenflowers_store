defmodule Edenflowers.Marketing.TrackingTag do
  @moduledoc """
  A UTM value Jennie has put on a shared link, like source `instagram` or
  campaign `mothers-day-2026`. The share drawer offers them, most recently used first, so
  the same channel is always spelled the same way: Umami counts `Instagram`
  and `instagram` as two sources.
  """

  use Ash.Resource,
    domain: Edenflowers.Marketing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @parameters [:source, :medium, :campaign]

  @suggestion_limit 6

  postgres do
    table "tracking_tags"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read]

    read :recent do
      description "Every tag used so far, most recently used first."
      prepare build(sort: [last_used_at: :desc])
    end

    action :suggestions, :map do
      description "The values the share drawer offers as chips for each parameter, most recently used first. " <>
                    "At most #{@suggestion_limit} per parameter, which fit on two rows of a phone; older tags " <>
                    "can still be typed. A new shop has none until Jennie copies her first tagged link."

      run fn _input, context ->
        with {:ok, tags} <- Ash.read(__MODULE__, Keyword.put(Ash.Context.to_opts(context), :action, :recent)) do
          by_parameter = Enum.group_by(tags, & &1.parameter, & &1.value)

          {:ok,
           Map.new(@parameters, fn parameter ->
             {parameter, by_parameter |> Map.get(parameter, []) |> Enum.take(@suggestion_limit)}
           end)}
        end
      end
    end

    destroy :forget do
      description "Jennie removes a tag from the share drawer's chips, such as a typo or a channel she " <>
                    "doesn't use. Links already shared with it keep working, and Umami keeps the visits they " <>
                    "brought."
    end

    action :tagged_url, :string do
      description "`url` with a `utm_` parameter for each of `tags` that has a value, normalised the way " <>
                    "stored tags are. With no tags it is `url` unchanged, a plain link."

      argument :url, :string do
        description "The full shop URL, without a language so each visitor lands on the page in their own."
        allow_nil? false
      end

      argument :tags, :map do
        description "Values keyed by :source, :medium and :campaign, as typed. Empty ones are left out."
        default %{}
      end

      run fn input, _context ->
        %{url: url, tags: tags} = input.arguments
        query = for {parameter, value} <- filled_in(tags), do: {"utm_#{parameter}", value}
        {:ok, if(query == [], do: url, else: url <> "?" <> URI.encode_query(query))}
      end
    end

    action :use_all do
      description "Remembers the tags on a link Jennie just copied, through `use`. Empty ones are skipped."

      argument :tags, :map do
        description "Values keyed by :source, :medium and :campaign, as typed."
        allow_nil? false
      end

      run fn input, context ->
        result =
          input.arguments.tags
          |> filled_in()
          |> Enum.map(fn {parameter, value} -> %{parameter: parameter, value: value} end)
          |> Ash.bulk_create(
            __MODULE__,
            :use,
            Ash.Context.to_opts(context) ++ [return_errors?: true, stop_on_error?: true]
          )

        case result do
          %Ash.BulkResult{status: :success} -> :ok
          %Ash.BulkResult{errors: errors} -> {:error, errors}
        end
      end
    end

    create :use do
      description "Remembers a tag when Jennie copies a link with it. The value is normalised the way " <>
                    "`normalize/1` does for the link itself, and using a known tag again moves it to the top."

      accept [:parameter, :value]
      upsert? true
      upsert_identity :unique_value
      upsert_fields [:last_used_at]

      change fn changeset, _context ->
        Ash.Changeset.update_change(changeset, :value, &normalize/1)
      end

      change set_attribute(:last_used_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :parameter, :atom do
      description "Which UTM parameter the value goes in: utm_source, utm_medium or utm_campaign."
      allow_nil? false
      public? true
      constraints one_of: [:source, :medium, :campaign]
    end

    attribute :value, :string do
      description "The value as it appears in links: lowercase, with hyphens for spaces."
      allow_nil? false
      public? true
      constraints max_length: 100
    end

    attribute :last_used_at, :utc_datetime_usec do
      description "When a copied link last carried this tag, to order the suggestions."
      allow_nil? false
    end

    timestamps()
  end

  identities do
    identity :unique_value, [:parameter, :value]
  end

  @doc """
  The value as it goes in a link: trimmed and lowercased, with runs of spaces
  turned into one hyphen, so "Mothers Day " becomes "mothers-day".
  """
  def normalize(value) when is_binary(value) do
    value |> String.trim() |> String.downcase() |> String.replace(~r/\s+/u, "-")
  end

  def normalize(nil), do: nil

  @doc "The `{parameter, value}` pairs of `tags` that have a value, normalised, in link order."
  def filled_in(tags) do
    for parameter <- @parameters,
        value = normalize(tags[parameter]),
        value not in [nil, ""],
        do: {parameter, value}
  end
end
