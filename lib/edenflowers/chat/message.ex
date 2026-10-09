defmodule Edenflowers.Chat.Message do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  oban do
    triggers do
      trigger :respond do
        actor_persister Edenflowers.Chat.ActorPersister
        action :respond
        queue :chat_responses
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Chat.Workers.Respond
        scheduler_module_name Edenflowers.Chat.Schedulers.Respond
        where expr(needs_response)
      end
    end
  end

  postgres do
    table "messages"
    repo Edenflowers.Repo

    references do
      reference :conversation, on_delete: :delete
      reference :response_to, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    read :for_conversation do
      pagination keyset?: true, required?: false
      argument :conversation_id, :uuid, allow_nil?: false

      prepare build(default_sort: [inserted_at: :desc])
      filter expr(conversation_id == ^arg(:conversation_id))
    end

    create :create do
      accept [:text]

      validate match(:text, ~r/\S/) do
        message "Message cannot be empty"
      end

      argument :conversation_id, :uuid do
        public? false
      end

      change Edenflowers.Chat.Changes.CreateConversationIfNotProvided
      change run_oban_trigger(:respond)
    end

    update :respond do
      accept []
      require_atomic? false
      transaction? false
      change Edenflowers.Chat.Changes.Respond
    end

    create :upsert_response do
      upsert? true
      accept [:id, :response_to_id, :conversation_id]
      argument :complete, :boolean, default: false
      argument :text, :string, allow_nil?: false, constraints: [trim?: false, allow_empty?: true]
      argument :tool_calls, {:array, :map}
      argument :tool_results, {:array, :map}

      change atomic_update(
               :text,
               {:atomic,
                expr(
                  if ^arg(:complete) do
                    ^arg(:text)
                  else
                    text <> ^arg(:text)
                  end
                )}
             )

      change atomic_update(
               :tool_calls,
               {:atomic,
                expr(
                  if not is_nil(^arg(:tool_calls)) do
                    fragment(
                      "? || ?",
                      tool_calls,
                      type(
                        ^arg(:tool_calls),
                        {:array, :map}
                      )
                    )
                  else
                    tool_calls
                  end
                )}
             )

      change atomic_update(
               :tool_results,
               {:atomic,
                expr(
                  if not is_nil(^arg(:tool_results)) do
                    fragment(
                      "? || ?",
                      tool_results,
                      type(
                        ^arg(:tool_results),
                        {:array, :map}
                      )
                    )
                  else
                    tool_results
                  end
                )}
             )

      change set_attribute(:text, arg(:text))
      change set_attribute(:complete, arg(:complete))
      change set_attribute(:source, :agent)
      change set_attribute(:tool_results, arg(:tool_results))
      change set_attribute(:tool_calls, arg(:tool_calls))

      upsert_fields [:complete]
    end
  end

  policies do
    # Lets the conversation naming job read the messages it summarises.
    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
    end

    bypass AshAi.Checks.ActorIsAshAi do
      authorize_if always()
    end

    policy always() do
      authorize_if relates_to_actor_via([:conversation, :user])
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint
    prefix "chat"

    # Covers :upsert_response too, which streams the agent's reply.
    publish_all :create, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        Map.take(message, [:text, :id, :source, :complete, :tool_calls, :tool_results])
      end
    end
  end

  attributes do
    timestamps()
    uuid_v7_primary_key :id, writable?: true

    attribute :text, :string do
      constraints allow_empty?: true, trim?: false
      public? true
      allow_nil? false
    end

    attribute :tool_calls, {:array, :map}
    attribute :tool_results, {:array, :map}

    attribute :source, :atom do
      constraints one_of: [:agent, :user]
      allow_nil? false
      public? true
      default :user
    end

    attribute :complete, :boolean do
      allow_nil? false
      default true
    end
  end

  relationships do
    belongs_to :conversation, Edenflowers.Chat.Conversation do
      public? true
      allow_nil? false
    end

    belongs_to :response_to, __MODULE__ do
      public? true
    end

    has_one :response, __MODULE__ do
      public? true
      destination_attribute :response_to_id
    end
  end

  calculations do
    calculate :needs_response, :boolean do
      calculation expr(source == :user and not exists(response))
    end
  end
end
