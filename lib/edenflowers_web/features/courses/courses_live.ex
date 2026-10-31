defmodule EdenflowersWeb.Courses.CoursesLive do
  @moduledoc """
  Public list of upcoming florist courses.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Translations
  alias EdenflowersWeb.Business
  alias EdenflowersWeb.Marketing.ContactDrawer

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    courses =
      [load: [:seats_left, :booking_open?], query: [sort: [date: :asc, start_time: :asc]]]
      |> Courses.list_upcoming_courses!()
      |> Translations.translate()

    {:ok,
     assign(socket,
       page_title: ~t"Floristry Courses in Vaasa",
       alternates: alternates("/#{language}/courses"),
       page_description:
         ~t"Floristry courses with Jennie at Eden Flowers in Vaasa. See upcoming dates and book your seat.",
       locale: Format.locale(),
       courses: courses
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      notice_bar={@notice_bar}
      alternates={@alternates}
    >
      <.container>
        <section class="flex flex-col gap-10 md:flex-row md:items-center md:justify-between md:gap-12 lg:gap-16">
          <div class="flex max-w-xl flex-col gap-6">
            <h1 class="page-title">{~t"Courses"}</h1>
            <p class="text-base-content/80 text-lg leading-relaxed">
              {~t"Come along and learn to make different kinds of floral arrangements. I show you the technique step by step and help you all the way, and of course you take your arrangement home. Materials and teaching are included, and you don't need any previous experience."}
            </p>
            <div class="mt-2">
              <.button href="#coming-up" variant="primary">{~t"See upcoming courses"}</.button>
            </div>
          </div>
          <%!-- Hidden on phones so the dates, which are what people came for, sit above the fold. --%>
          <div class="hidden flex-shrink-0 md:block md:w-80 lg:w-96 xl:w-[28rem]">
            <.image
              src="local:///jennie_4.jpg"
              alt=""
              width={1000}
              height={1250}
              sizes="(min-width: 1280px) 28rem, (min-width: 1024px) 24rem, 20rem"
              class="aspect-[4/5] object-[50%_35%] w-full object-cover"
            />
          </div>
        </section>

        <section
          class="mt-12 sm:mt-16"
          aria-labelledby="coming-up"
        >
          <div>
            <h2 id="coming-up" class="section-title">{~t"Coming up"}</h2>

            <div :if={@courses == []} class="mt-6" data-testid="no-courses">
              <p class="text-base-content/80 max-w-prose">
                {~t"There are no courses on the calendar right now. I announce new dates in the newsletter first."}
              </p>
              <.button href="#newsletter" variant="text" class="mt-4">{~t"Sign up for the newsletter"}</.button>
            </div>

            <ol :if={@courses != []} class="border-base-content/12 mt-6 border-b" data-testid="courses-list">
              <li :for={course <- @courses} class="border-base-content/12 border-t">
                <.course_row course={course} locale={@locale} />
              </li>
            </ol>

            <div :if={@courses != []} class="mt-6 flex flex-wrap items-baseline gap-x-4 gap-y-2 text-sm">
              <p class="text-base-content/70">{~t"I announce new dates in the newsletter first."}</p>
              <.button href="#newsletter" variant="text">{~t"Sign up for the newsletter"}</.button>
            </div>
          </div>
        </section>

        <section
          class="bg-cream text-cream-content -mx-4 mt-16 grid sm:mx-0 sm:mt-24 md:grid-cols-[2fr_3fr]"
          aria-labelledby="groups"
        >
          <.image
            src="local:///image_5.jpg"
            alt=""
            width={1500}
            height={1000}
            sizes="(min-width: 768px) 40vw, 100vw"
            class="aspect-[4/3] object-[69%_30%] h-full w-full object-cover md:aspect-auto"
          />

          <div class="flex flex-col items-start gap-6 px-4 py-12 sm:px-10 md:justify-center md:px-12 md:py-16 lg:px-16 lg:py-20">
            <.flower name="flower-30" class="text-cream-content/60 h-12 w-12" />
            <h2 id="groups" class="section-title text-balance">{~t"Courses for private groups"}</h2>
            <p class="max-w-prose text-lg leading-relaxed">
              {~t"I also run courses for private groups, for example at a workplace Christmas party, your staff wellbeing day or a hen party. We can meet in the café space at Minimossen or at your own premises. In summer, making flower crowns outdoors in a park works well."}
            </p>
            <p class="max-w-prose">{~t"Get in touch and we'll find a course and a day that suit your group."}</p>
            <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
              <.button phx-click={ContactDrawer.open()} variant="primary">{~t"Send me a message"}</.button>
              <a href={"tel:#{Business.phone()}"} class="link-underline-static-body whitespace-nowrap">
                {Business.phone_display()}
              </a>
            </div>
          </div>
        </section>
      </.container>

      <.live_component module={ContactDrawer} id="contact-drawer" />
    </Layouts.app>
    """
  end

  attr :course, :map, required: true
  attr :locale, :any, required: true

  defp course_row(assigns) do
    ~H"""
    <div class="grid-cols-[3.5rem_minmax(0,1fr)] relative grid items-start gap-x-4 gap-y-4 py-7 sm:grid-cols-[4rem_6rem_minmax(0,1fr)] sm:gap-x-6 lg:grid-cols-[4rem_8rem_minmax(0,1fr)_11rem] lg:gap-x-8">
      <div class="flex flex-col gap-4 sm:contents">
        <time
          datetime={Date.to_iso8601(@course.date)}
          aria-label={Format.weekday_date(@course.date, @locale)}
          class="flex flex-col gap-1 pt-1 tabular-nums"
        >
          <span class="font-serif text-4xl leading-none">{@course.date.day}</span>
          <span class="text-base-content/70 text-sm">{Format.short_month(@course.date, @locale)}</span>
        </time>

        <.link
          navigate={~q"/#{language}/courses/#{@course.id}"}
          aria-label={@course.name}
          class="block"
        >
          <.image
            src={@course.image_slug}
            alt=""
            width={256}
            height={256}
            sizes="(min-width: 1024px) 8rem, (min-width: 640px) 6rem, 3.5rem"
            class="bg-cream aspect-square w-full object-cover"
          />
        </.link>
      </div>

      <div class="min-w-0">
        <h3 class={["card-heading text-balance", !@course.booking_open? && "text-base-content/70"]}>
          <.link
            navigate={~q"/#{language}/courses/#{@course.id}"}
            class="link-underline-hover"
          >
            {@course.name}
          </.link>
        </h3>
        <p class="text-base-content/80 mt-2 text-sm tabular-nums">
          {Format.time(@course.start_time, @locale)}–{Format.time(@course.end_time, @locale)}
          <span aria-hidden="true"> · </span>
          <span data-testid="course-language">{taught_in(@course.language)}</span>
        </p>
        <p class="text-base-content/70 mt-1 text-sm">{@course.location_name}</p>
        <p
          :if={@course.description not in [nil, ""]}
          class="text-base-content/80 line-clamp-2 mt-3 max-w-lg text-sm leading-relaxed"
        >
          {@course.description}
        </p>
      </div>

      <div class="col-start-2 flex flex-col items-start gap-2 sm:col-start-3 lg:col-start-4 lg:row-start-1 lg:items-end lg:text-right">
        <p class="text-base-content font-serif text-xl tabular-nums">
          {~t"#{price = Format.storefront_price(@course.price, @locale)} per person"}
        </p>
        <p class="text-base-content/70 text-sm" data-testid="course-availability">{availability(@course)}</p>
        <.button
          :if={@course.booking_open?}
          navigate={~q"/#{language}/courses/#{@course.id}" <> "#book"}
          variant="primary"
          size="sm"
          class="min-h-11 mt-1"
          aria-label={~t"Book a place" <> ": " <> @course.name}
        >
          {~t"Book a place"} <span aria-hidden="true">→</span>
        </.button>
      </div>
    </div>
    """
  end

  defp taught_in(:sv), do: ~t"In Swedish"
  defp taught_in(:fi), do: ~t"In Finnish"
  defp taught_in(:en), do: ~t"In English"

  defp availability(%{seats_left: seats_left}) when seats_left <= 0, do: ~t"Fully booked"
  defp availability(%{booking_open?: false}), do: ~t"Booking closed"
  defp availability(%{seats_left: seats_left}), do: ~t"#{count = seats_left} place(s) left"N
end
