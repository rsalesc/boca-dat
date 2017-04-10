require 'nokogiri'
require 'htmlentities'
require 'tmpdir'

$THRESHOLD = 100

def fix_html(s)
  HTMLEntities.new.decode(s)
end

class Problem
  attr_accessor :id
  attr_accessor :name
end

class Team
  attr_accessor :id
  attr_accessor :name
end

class Submission
  attr_accessor :id
  attr_accessor :problem
  attr_accessor :team
  attr_accessor :attempt
  attr_accessor :time # in minutes
  attr_accessor :verdict

  def is_good
    return @verdict == "AC"
  end
end

class Contest
  attr_accessor :name
  attr_accessor :duration # in minutes
  attr_accessor :problems
  attr_accessor :teams
  attr_accessor :submissions

  def initialize(name="Unnamed", duration=300)
    @name = name
    @duration = duration
    @problems = []
    @teams = []
    @submissions = []
  end

  def get_problem_count
    return problems.length
  end

  def get_team_count
    return teams.length
  end

  def get_submission_count
    return submissions.length
  end
end

class TestsysOutput
  attr_accessor :f
  def initialize(f)
    @f = f
  end

  def output(contest)
    @f.puts("\x1A")
    @f.puts("@contest \"#{contest.name}\"")
    @f.puts("@contlen #{contest.duration}")
    @f.puts("@problems #{contest.get_problem_count}")
    @f.puts("@teams #{contest.get_team_count}")
    @f.puts("@submissions #{contest.get_submission_count}")

    contest.problems.each do |p|
      self.output_problem(p)
    end

    contest.teams.each do |t|
      self.output_team(t)
    end

    contest.submissions.each do |s|
      self.output_submission(s)
    end
  end

  def output_problem(p)
    @f.puts("@p #{p.id},\"#{p.name}\",20,0")
  end

  def output_team(t)
    @f.puts("@t #{t.id},0,1,\"#{t.name}\"")
  end

  def output_submission(s)
    @f.puts("@s #{s.team.id},#{s.problem.id},#{s.attempt},#{s.time},#{self.get_verdict(s.verdict)}")
  end

  def get_verdict(v)
    return v
  end
end

$BOCA_VERDICT = {
  1 => "OK",
  2 => "CE",
  3 => "RT",
  4 => "TL",
  5 => "PE",
  6 => "WA",
  7 => "RJ"
}

class BocaParser
  attr_accessor :f
  def initialize(f)
    @f = f
    @doc = Nokogiri::XML(f)
  end

  def get_contest
    no = @doc.xpath("//CONTESTREC").first
    c = Contest.new

    c.name = fix_html(no.xpath("name[1]/text()").first.to_s)
    c.duration = no.xpath("duration[1]/text()").first.to_s.to_i/60

    c.problems, problems_hash = self.get_problems
    c.teams, teams_hash = self.get_teams
    c.submissions = self.get_submissions(teams_hash, problems_hash)

    return c
  end

  def get_problems
    nos = @doc.xpath("//PROBLEMREC")
    ps = []
    hash = {}

    nos.each do |no|
      p = Problem.new
      number = no.xpath("number[1]/text()").first.to_s.to_i
      p.id = no.xpath("name[1]/text()").first.to_s
      p.name = fix_html(no.xpath("fullname[1]/text()").first.to_s)
      ps << p
      hash[number] = p
    end

    return [ps, hash]
  end

  def get_teams
    nos = @doc.xpath("//USERREC")
    res = []
    hash = {}

    nos.each do |no|
      type = no.xpath("type[1]/text()").first.to_s
      if type != "team" then
        next
      end

      t = Team.new
      t.id = no.xpath("user[1]/text()").first.to_s.to_i
      t.name = fix_html(no.xpath("userfull[1]/text()").first.to_s)

      res << t
      hash[t.id] = t
    end

    return [res, hash]
  end

  def get_submissions(teams, problems)
    nos = @doc.xpath("//RUNREC")
    res = []
    counting = {}

    nos.each do |no|
      user_id = no.xpath("user[1]/text()").first.to_s.to_i
      problem_id = no.xpath("problem[1]/text()").first.to_s.to_i

      s = Submission.new
      s.id = no.xpath("number[1]/text()").first.to_s.to_i
      s.team = teams[user_id]
      s.problem = problems[problem_id]
      s.time = no.xpath("rundatediff[1]/text()").first.to_s.to_i
      s.attempt = (counting[[user_id, problem_id]] || 0) + 1
      s.verdict = $BOCA_VERDICT[no.xpath("runanswer[1]/text()").first.to_s.to_i]

      counting[[user_id, problem_id]] = s.attempt

      res << s
    end

    return res
  end

  def parse
    return self.get_contest
  end
end

if __FILE__ == $0 then
  Dir.mktmpdir{|dir|
    tmp_path = File.join(dir, "export.dat")
    
    File.open(tmp_path, "w"){|f|
      IO.foreach("export.dat") do |line|
        unless line.size > $THRESHOLD
          f << line
        end
      end
    }

    File.open(tmp_path){|f|
      parser = BocaParser.new(f)
      contest = parser.parse
      File.open("contest.dat", "w"){|g|
        out = TestsysOutput.new(g)
        out.output(contest)
      }
    }  
  }
end


