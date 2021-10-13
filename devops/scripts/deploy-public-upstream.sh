#!/bin/bash
# This script is pretty tailored to assuming it's running in the CircleCI environment / a fresh git clone.
# It mirrors most commits from `pantheon-systems/drupal-recommended:release` to `pantheon-upstreams/drupal-recommended`.

set -euo pipefail

. devops/scripts/commit-type.sh

# At the end of this process, release-source in pantheon-upstreams/drupal-recommended will be the same than release in pantheon-systems/drupal-recommended.

git remote add public "$UPSTREAM_REPO_REMOTE_URL"
git fetch public
git checkout "${CIRCLE_BRANCH}"

# List commits between release-source and HEAD, in reverse
newcommits=$(git log release-source..HEAD --reverse --pretty=format:"%h")
commits=()

# Identify commits that should be released
for commit in $newcommits; do
  commit_type=$(identify_commit_type "$commit")
  if [[ $commit_type == "normal" ]] ; then
    commits+=($commit)
  fi

  if [[ $commit_type == "mixed" ]] ; then
    2>&1 echo "Commit ${commit} contains both release and nonrelease changes. Cannot proceed."
    exit 1
  fi
done

# If nothing found to release, bail without doing anything.
if [[ ${#commits[@]} -eq 0 ]] ; then
  echo "No new commits found to release"
  echo "https://i.kym-cdn.com/photos/images/newsfeed/001/240/075/90f.png"
  exit 1
fi

# Cherry-pick commits not modifying circle config onto the release branch
git checkout -b release-source --track public/release-source
git pull

if [[ "$CIRCLECI" != "" ]]; then
  git config --global user.email "bot@getpantheon.com"
  git config --global user.name "Pantheon Automation"
fi

for commit in "${commits[@]}"; do
  if [[ -z "$commit" ]] ; then
    continue
  fi
  # Sync commits from release (pantheon-systems/drupal-recommended) to release-source (pantheon-recommended/drupal-recommended).
  git cherry-pick "$commit" 2>&1
  # Product request - single commit per release
  # The commit message from the last commit will be used.
  git log --format=%B -n 1 "$commit" > /tmp/commit_message
done

# Get a patch with the diff between release-pointer and current HEAD and apply it.
git diff release-pointer..HEAD > all-changes.patch
git checkout -b public --track public/master
git apply < all-changes.patch
git add -A .

git commit -F /tmp/commit_message --author='Pantheon Automation <bot@getpantheon.com>'

# Push released commits to a few branches on the upstream repo.
# Since all commits to this repo are automated, it shouldn't hurt to put them on both branch names.
release_branches=('master' 'main')
for branch in "${release_branches[@]}"; do
  git push public public:"$branch"
done

# Push updated release-source branch now that previous stuff has worked.
git checkout release-source
git push public release-source

# Update the release-pointer.
git tag -f -m 'Last commit set on upstream repo' release-pointer HEAD

# Push release-pointer
git push -f origin release-pointer
