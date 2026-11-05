defmodule Edenflowers.Courses.CourseTest do
  use Edenflowers.DataCase, async: true

  import Generator

  test "a photographer website needs a name and an HTTP or HTTPS address" do
    course = generate(course())

    for url <- ["example.com", "javascript:alert(1)", "//example.com", "https://", "https://example.com/a b"] do
      assert {:error, _} =
               Ash.update(course, %{photo_credit_name: "Anna", photo_credit_url: url}, authorize?: false)
    end

    assert {:error, _} = Ash.update(course, %{photo_credit_url: "https://example.com"}, authorize?: false)
  end

  for {season, date, utc_end} <- [
        {:winter, ~D[2026-01-15], ~U[2026-01-15 11:00:00Z]},
        {:summer, ~D[2026-07-15], ~U[2026-07-15 10:00:00Z]},
        {:midnight, ~D[2026-07-15], ~U[2026-07-14 21:30:00Z]}
      ] do
    @tag date: date, utc_end: utc_end, end_time: if(season == :midnight, do: ~T[00:30:00], else: ~T[13:00:00])
    test "course ends at its exact Helsinki end time in #{season}", ctx do
      course = generate(course(date: ctx.date, end_time: ctx.end_time))

      before_end = Ash.load!(course, [ended?: [now: DateTime.add(ctx.utc_end, -1, :second)]], authorize?: false)
      at_end = Ash.load!(course, [ended?: [now: ctx.utc_end]], authorize?: false)
      after_end = Ash.load!(course, [ended?: [now: DateTime.add(ctx.utc_end, 1, :second)]], authorize?: false)

      refute before_end.ended?
      assert at_end.ended?
      assert after_end.ended?
    end
  end

  describe "a course's slug" do
    test "is made from its name, and a repeat run of the same course gets -2" do
      assert generate(course(name: "Spring wreaths")).slug == "spring-wreaths"
      assert generate(course(name: "Spring wreaths!")).slug == "spring-wreaths-2"
    end

    test "edited, sends links with the old slug and the id to the new one" do
      course = generate(course(name: "Spring wreaths"))
      course = course |> Ash.Changeset.for_update(:update, %{slug: "wreaths-2027"}) |> Ash.update!(authorize?: false)

      assert Edenflowers.Courses.current_course_slug!("spring-wreaths") == "wreaths-2027"
      assert Edenflowers.Courses.current_course_slug!(course.id) == "wreaths-2027"
    end

    for slug_input <- [:omitted, :unchanged, :normalized] do
      test "a stale unrelated save preserves redirects with #{slug_input} slug input" do
        stale = generate(course(name: "Spring wreaths"))
        Ash.update!(stale, %{slug: "wreaths-2027"}, action: :update, authorize?: false)
        params = %{name: "Summer wreaths"}

        params =
          case unquote(slug_input) do
            :omitted -> params
            :unchanged -> Map.put(params, :slug, stale.slug)
            :normalized -> Map.put(params, :slug, "Spring Wreaths!")
          end

        Ash.update!(stale, params, action: :update, authorize?: false)

        assert Edenflowers.Courses.current_course_slug!(stale.id) == "wreaths-2027"
        assert Edenflowers.Courses.current_course_slug!("spring-wreaths") == "wreaths-2027"
        assert Edenflowers.Courses.current_course_slug!("wreaths-2027") == nil
      end
    end
  end
end
