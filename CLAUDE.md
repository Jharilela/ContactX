# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ContactX is a mobile-first personal CRM for intelligent contact and relationship management. It's an AI-powered networking app that helps users maintain relationships with intention, not just store contacts.

**Core Value Proposition**: Stay top of mind, remember everyone who matters, and never lose touch.

## Tech Stack

### Mobile App
- **React Native** with **TypeScript** and **Expo** for cross-platform development
- Start with iOS beta (Phase 1), expand to Android (Phase 3)

### Backend
- **Node.js / Express** API server
- **PostgreSQL** for relational data (contacts, relationships, notes)
- **Redis** for caching and session management

### AI/ML
- **OpenAI API (GPT-4)** for relationship insights and follow-up suggestions
- **Vector database** for semantic search capabilities
- On-device ML for privacy-first features

### Infrastructure
- **AWS / Railway** for hosting
- **Cloudflare** for CDN and security
- **Vercel** for admin dashboard

## Development Commands

```bash
# Install dependencies (always update package-lock.json when adding new libraries)
npm install

# Start Expo development server
npm start

# Run on specific platform
npm run ios
npm run android

# Testing
npm test

# Production build
npm run build
```

## Architecture & Project Structure

### Phase-Based Development

The project follows a phased rollout strategy:

**Phase 1 (MVP - Months 1-2)**: Local contact import, notes, basic reminders, tagging
**Phase 2 (Intelligence - Months 3-4)**: Relationship timeline, touch tracking, AI suggestions
**Phase 3 (Monetization - Months 5-6)**: Freemium launch, premium features, multi-device sync
**Phase 4 (Scale - Months 7-12)**: Team features, social integrations, event networking

### Core Data Models

**Contact**
- Basic info (name, phone, email, etc.)
- Rich context (role, company, how you met)
- Tags and categories
- Relationship strength/priority

**Interaction/Touch Point**
- Timestamp of last contact
- Communication channel
- Notes/context from interaction
- Frequency tracking

**Reminder**
- Smart follow-up suggestions
- User-defined check-ins
- AI-generated nudges

**Notes**
- Contextual information
- Conversation history
- Personal details

### Key Features by Phase

**Phase 1 (Current Focus)**:
- Contact import from device
- Rich note-taking per contact
- Smart reminder system
- Basic tagging

**Phase 2**:
- AI-powered search
- Relationship tracking dashboard
- Touch point history
- Context tags (role, company, meeting source)

**Phase 3**:
- AI follow-up suggestions
- Relationship insights
- Proactive reminders
- Memory assistant

**Phase 4**:
- Contact sharing/introductions
- Multi-device sync
- Team contact lists
- Event networking features

## Business Model Context

**Free Tier**: Import contacts, smart reminders, AI memory, basic notes/tags
**Pro Tier ($1/user/month)**: Advanced intelligence, unlimited AI insights, sync, sharing

Target users are network-dependent professionals: entrepreneurs, sales/partnerships, investors, consultants, recruiters, executives.

## Database Migrations

When creating new SQL migration files in the migration folder, always increase the sequential number at the start.

## Development Notes

- Focus on **lightweight, fast UX** (not a heavy enterprise CRM)
- **Privacy-first**: Sensitive contact data must be handled securely
- **AI integration**: Leverage GPT-4 for smart insights, but keep user in control
- **Mobile-first**: All features must work perfectly on mobile before web
- **Viral mechanics**: Build features that encourage sharing (intros, referrals)

## Target Metrics

**Engagement**: DAU, contacts per user, reminders acted upon
**Retention**: Weekly retention rate, monthly churn, feature adoption
**Revenue**: Free→Paid conversion, MRR, LTV
**Growth**: K-factor, referral rate, organic acquisition
