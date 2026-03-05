-- ============================================
-- MENTORSHIP CHECK-IN SUBMISSIONS
-- Run this in Supabase SQL Editor (all at once)
-- Project: jiquevvzrdavgqonvvug (Kelly Mentorship)
-- ============================================

-- Enable pg_net for server-side HTTP calls (Telegram notifications)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================
-- TABLE: checkin_submissions
-- ============================================
CREATE TABLE checkin_submissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Student info
  student_name TEXT NOT NULL,
  audit_date DATE,
  birth_date DATE,
  birth_time TEXT,
  birth_place TEXT,

  -- Pillar scores (calculated averages out of 5)
  intuition_score NUMERIC(3,2),
  health_score NUMERIC(3,2),
  business_score NUMERIC(3,2),
  overall_score NUMERIC(3,2),

  -- All 15 individual question scores (1-5)
  scores_detail JSONB NOT NULL DEFAULT '{}',

  -- Open-ended text responses
  open_responses JSONB NOT NULL DEFAULT '{}',

  -- Sleep environment data
  sleep_data JSONB NOT NULL DEFAULT '{}',

  -- Business snapshot (offer, audience, pricing, website, socials, tools)
  business_snapshot JSONB NOT NULL DEFAULT '{}',

  -- Management
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN (
    'new', 'analyzed', 'onboarded'
  )),
  notes TEXT,
  analysis_complete BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_checkins_status ON checkin_submissions(status);
CREATE INDEX idx_checkins_created ON checkin_submissions(created_at DESC);
CREATE INDEX idx_checkins_name ON checkin_submissions(student_name);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE checkin_submissions ENABLE ROW LEVEL SECURITY;

-- Form submissions (anon INSERT)
CREATE POLICY "Public can submit check-ins"
  ON checkin_submissions FOR INSERT
  WITH CHECK (true);

-- Command Centre reads (anon SELECT)
CREATE POLICY "Public can read check-ins"
  ON checkin_submissions FOR SELECT
  USING (true);

-- Command Centre status/notes updates (anon UPDATE)
CREATE POLICY "Public can update check-ins"
  ON checkin_submissions FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- ============================================
-- AUTO-UPDATE updated_at TRIGGER
-- ============================================
CREATE OR REPLACE FUNCTION update_checkin_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_checkins_updated_at
  BEFORE UPDATE ON checkin_submissions
  FOR EACH ROW EXECUTE FUNCTION update_checkin_updated_at();

-- ============================================
-- TELEGRAM NOTIFICATION ON NEW CHECK-IN
-- ============================================
CREATE OR REPLACE FUNCTION notify_telegram_new_checkin()
RETURNS TRIGGER AS $$
DECLARE
  message_text TEXT;
  intuition_vibe TEXT;
  health_vibe TEXT;
  business_vibe TEXT;
  overall_vibe TEXT;
  website TEXT;
  socials TEXT;
BEGIN
  -- Score vibes
  CASE
    WHEN NEW.intuition_score >= 4.5 THEN intuition_vibe := 'This is her zone';
    WHEN NEW.intuition_score >= 3.5 THEN intuition_vibe := 'Good bones';
    WHEN NEW.intuition_score >= 2.5 THEN intuition_vibe := 'Messy middle';
    ELSE intuition_vibe := 'Starting point';
  END CASE;

  CASE
    WHEN NEW.health_score >= 4.5 THEN health_vibe := 'This is her zone';
    WHEN NEW.health_score >= 3.5 THEN health_vibe := 'Good bones';
    WHEN NEW.health_score >= 2.5 THEN health_vibe := 'Messy middle';
    ELSE health_vibe := 'Starting point';
  END CASE;

  CASE
    WHEN NEW.business_score >= 4.5 THEN business_vibe := 'This is her zone';
    WHEN NEW.business_score >= 3.5 THEN business_vibe := 'Good bones';
    WHEN NEW.business_score >= 2.5 THEN business_vibe := 'Messy middle';
    ELSE business_vibe := 'Starting point';
  END CASE;

  CASE
    WHEN NEW.overall_score >= 4.5 THEN overall_vibe := 'Aligned';
    WHEN NEW.overall_score >= 3.5 THEN overall_vibe := 'Building';
    WHEN NEW.overall_score >= 2.5 THEN overall_vibe := 'Awakening';
    ELSE overall_vibe := 'Beginning';
  END CASE;

  -- Extract website and socials
  website := COALESCE(NEW.business_snapshot->>'website', 'Not provided');
  socials := COALESCE(NEW.business_snapshot->>'socials', 'Not provided');

  message_text :=
    '<b>NEW CHECK-IN SUBMITTED</b>' || chr(10) || chr(10)
    || '<b>' || NEW.student_name || '</b>' || chr(10)
    || 'Date: ' || COALESCE(NEW.audit_date::text, 'Not set') || chr(10) || chr(10)
    || '<b>SCORES</b>' || chr(10)
    || 'Intuition: ' || NEW.intuition_score || '/5 - ' || intuition_vibe || chr(10)
    || 'Health: ' || NEW.health_score || '/5 - ' || health_vibe || chr(10)
    || 'Business: ' || NEW.business_score || '/5 - ' || business_vibe || chr(10)
    || '<b>Overall: ' || NEW.overall_score || '/5 - ' || overall_vibe || '</b>' || chr(10) || chr(10)
    || '<b>BUSINESS SNAPSHOT</b>' || chr(10)
    || 'Offer: ' || COALESCE(LEFT(NEW.business_snapshot->>'offer', 200), 'Not provided') || chr(10)
    || 'Audience: ' || COALESCE(LEFT(NEW.business_snapshot->>'audience', 200), 'Not provided') || chr(10)
    || 'Price: ' || COALESCE(NEW.business_snapshot->>'price', 'Not provided') || chr(10)
    || 'Website: ' || website || chr(10)
    || 'Socials: ' || socials || chr(10) || chr(10)
    || 'Run <code>/onboard ' || NEW.student_name || '</code> for full analysis';

  PERFORM net.http_post(
    url := 'https://api.telegram.org/bot8370823351:AAFIS2oYqnoqm_y4xaZlNMqb4SaFnapDu7s/sendMessage',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := json_build_object(
      'chat_id', '6783708099',
      'text', message_text,
      'parse_mode', 'HTML'
    )::jsonb
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_new_checkin
  AFTER INSERT ON checkin_submissions
  FOR EACH ROW EXECUTE FUNCTION notify_telegram_new_checkin();
