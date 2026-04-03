What approach should I take to assure the best outcome.                                     
                                                                                            
Ideally I would like to break this down into chunks of work that have a meaningful outcome  
for me so I can see results and validate as we go                                           
                                                                                            
Recommend a plan for building this application.                                             

● Good question to ask before starting. Here's my recommendation.

  ---                                                                                       
  Before writing a single line of code: create CLAUDE.md
                                                                                            
  This is the most important step. Claude Code automatically reads CLAUDE.md at the root of
  every session. Without it, each new session starts cold and you'll waste tokens           
  re-establishing context. Put the key decisions in there: schema division, stack, tile
  security rule, Drizzle/postgres.js split, Phantom theming order. Think of it as the       
  standing brief that every session inherits.                       
                                               
  ---
  Guiding principles for this project
                                     
  One session, one phase. Each session below has a single clear scope. Don't let a session
  drift into the next phase — finish, verify, commit, then start fresh.                     
   
  Verify before you build on top. Each phase ends with something you can actually check. If 
  it doesn't work, fix it before proceeding. Building phase 4 on a broken phase 3 compounds
  problems quickly.                                                                         
                                                                    
  Commit between phases. Clean git history = safe rollback points. If a session goes wrong  
  you can reset to the last good state without losing earlier work.
                                                                                            
  Read before edit. Claude Code is instructed to read files before modifying them. Hold it  
  to this — if it starts editing files it hasn't read, push back.
                                                                                            
  ---                                                               
  The phases                                   
                                                                                            
  Phase 1 — Project scaffold + infrastructure
                                                                                            
  Scope: pnpm monorepo, Docker Compose, Postgres/PostGIS/Martin running.                    
                                               
  Done when: docker compose up starts cleanly, psql connects, Martin responds at its        
  internal URL, pnpm install succeeds across the workspace.         
                                                                                            
  Why first: Everything else depends on this. A working database and tile server means all  
  subsequent phases have something real to test against.
                                                                                            
  ---                                                                                       
  Phase 2 — Database schemas                   
                                                                                            
  Scope: packages/db with both DDL files (iam and network_model), init SQL that runs on
  container startup, and a small seed script with one role, one user, and a handful of test 
  network objects with geometries.
                                                                                            
  Done when: You can psql in and SELECT from iam.users, network_model.object, and           
  network_model.class_definition. The seed data has real WGS84 coordinates so Martin has
  something to serve.                                                                       
                                                                    
  Why here: Schema is the foundation of auth, tiles, and the UI. Get it right before        
  anything touches it.
                                                                                            
  ---                                                               
  Phase 3 — Authentication 

	  Practical advice: when you reach Phase 3, before writing any code, run:                                                                               
	  npm show next-auth@beta version                                                                                                                       
	  Then check the Auth.js changelog or provider source for that exact version to confirm the Entra ID slug. The Google provider (AUTH_GOOGLE_ID,         
	  AUTH_GOOGLE_SECRET) has been stable and you can trust those as written.                                                                               
                                                                                
                    
                          
  Scope: Auth.js v5 configured for one provider (Google first — simpler), JIT provisioning
  in the signIn callback, jwt/session callbacks attaching role, TypeScript type             
  augmentation, basic sign-in/sign-out pages styled with Phantom tokens.
                                                                                            
  Done when: You can sign in with a Google account, see a new row in iam.users, and         
  console.log(session) shows session.user.role populated. Sign-in page looks on-brand.
                                                                                            
  Why one provider first: Getting one OIDC flow working end-to-end is the milestone. Adding 
  Microsoft Entra ID is a config change once the pattern is proven.
                                                                                            
  ---                                                               
  Phase 4 — Tile proxy                         
                      
  Scope: The Route Handler at app/api/tiles/[...path]/route.ts, Docker network isolation for
   Martin (no host port mapping), MARTIN_INTERNAL_URL env var, role injection, and the proxy
   header scrubbing guardrail.
                                                                                            
  Done when: curl with a valid session cookie to /api/tiles/... returns a protobuf tile.    
  curl without a cookie returns 401. A direct curl to Martin's port from the host fails
  (network isolation confirmed).                                                            
                                                                    
  Why before the map: Proving the security boundary works in isolation — without a browser —
   is much easier to debug than chasing it through MapLibre.
                                                                                            
  ---                                                               
  Phase 5 — Map renders                        
                       
  Scope: MapLibre initialised in a React client component, authenticated vector tile source
  pointing at the proxy, a basic layer style, map fills the viewport.                       
   
  Done when: You open the browser, sign in, and see your seed network objects rendered on   
  the map. Unauthenticated visit redirects to sign-in.              
                                                                                            
  This is the first "wow" moment — the core value of the application is visible for the     
  first time.                                  
                                                                                            
  ---                                                               
  Phase 6 — PostGIS function sources + attribute-level RBAC
                                                                                            
  Scope: PostGIS SQL functions in packages/db that accept user_role and return different
  attributes per role, Martin config pointing to these functions instead of raw tables, a   
  second test role with restricted attributes to verify redaction works.
                                                                                            
  Done when: Two browser sessions with different roles see different data in the tile       
  attributes (verify with MapLibre's queryRenderedFeatures in the console).
                                                                                            
  Why its own phase: This is the most security-critical piece and needs isolated, careful   
  testing.                                     
                                                                                            
  ---                                                               
  Phase 7 — UI shell + design system           
                                                                                            
  Scope: shadcn init with Phantom tokens applied first, sidebar with layer controls,
  attribute inspector panel, top navigation bar, sign-in page — all using the Phantom       
  component classes from tt-ui-style.                               
                                                                                            
  Done when: The app looks like the style guide. A non-technical person looking at it would 
  recognise it as a finished product shell, not a scaffold.
                                                                                            
  ---                                                               
  Phase 8 — Sample network + end-to-end validation
                                                                                            
  Scope: A realistic seed dataset (a small electrical network — say 20–30 objects with real
  relationships and geometries), layer styling that reflects object types, basic hover      
  tooltip showing attributes.                                       
                                                                                            
  Done when: You can open the app, see a recognisable network on the map, hover a node and  
  see its attributes, and confirm that a restricted-role user cannot see sensitive fields.
                                                                                            
  ---                                                               
  Summary table                                
               
  ┌───────┬────────────────────────────────┬─────────────────────────────────────────────┐
  │ Phase │          Deliverable           │                 Verified by                 │  
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤
  │ 1     │ Monorepo + Docker              │ docker compose up + Martin responds         │  
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤
  │ 2     │ Both DB schemas + seed data    │ psql SELECT on both schemas                 │  
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤  
  │ 3     │ Auth + JIT + role in session   │ Sign in, check iam.users, log session       │  
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤  
  │ 4     │ Tile proxy + security boundary │ curl with/without cookie + Martin isolation │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤  
  │ 5     │ Map renders tiles              │ Browser — see objects on map                │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤  
  │ 6     │ RBAC attribute redaction       │ Two roles, different attributes in console  │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤  
  │ 7     │ UI shell + Phantom design      │ Visual review against style guide           │
  ├───────┼────────────────────────────────┼─────────────────────────────────────────────┤  
  │ 8     │ Realistic seed + tooltips      │ Full end-to-end user walkthrough            │
  └───────┴────────────────────────────────┴─────────────────────────────────────────────┘  
                                                                    
  Each phase is a commit. Each commit is a working application.                             
                                                                    
---
