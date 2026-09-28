defmodule Edenflowers.Chat.Conversation do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  oban do
    triggers do
      trigger :name_conversation do
        action :generate_name
        queue :conversations
        lock_for_update? false
        worker_module_name Edenflowers.Chat.Workers.NameConversation
        scheduler_module_name Edenflowers.Chat.Schedulers.NameConversation
        where expr(needs_title)
        default_actor Edenflowers.Actors.system_actor()
      end
    end
  end

  postgres do
    table "conversations"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title]
      change relate_actor(:user)
    end

    update :generate_name do
      accept []
      transaction? false
      require_atomic? false
      change Edenflowers.Chat.Changes.GenerateName
    end

    read :my_conversations do
      filter expr(user_id == ^actor(:id))
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([:read, :generate_name])
    end

    bypass AshAi.Checks.ActorIsAshAi do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint
    prefix "chat"

    publish_all :create, ["conversations", :user_id] do
      transform & &1.data
    end

    publish_all :update, ["conversations", :user_id] do
      transform & &1.data
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :messages, Edenflowers.Chat.Message do
      public? true
    end

    belongs_to :user, Edenflowers.Accounts.User do
      public? true
      allow_nil? false
    end
  end

  calculations do
    calculate :needs_title, :boolean do
      calculation expr(
                    is_nil(title) and (count(messages) > 3 or (count(messages) > 1 and inserted_at < ago(10, :minute)))
                  )
    end
  end
end
