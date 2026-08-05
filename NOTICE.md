# Attribution and distribution notice

This customized plugin is derived from:

- `asxelot/wordwise.koplugin`
  (`https://github.com/asxelot/wordwise.koplugin`)

The upstream repository was supplied as the technical starting point and does
not publish an explicit open-source license file. The owner of this maintenance
repository confirms that the upstream author privately granted permission to
modify and redistribute this customized code-only fork. That private
permission is the basis for this repository's public distribution.

Public visibility does not by itself grant downstream recipients an
open-source license to upstream-derived portions of this repository. Anyone
who intends to reuse, modify, or redistribute those portions should obtain
their own permission or rely on rights that independently apply to them.

The updater implementation and maintenance changes in this repository were
prepared independently for this project. Reading Insights and Bookshelf
updater behavior was reviewed only as a compatibility reference for KOReader
APIs.

No English–Vietnamese database is committed to this Git source tree. GitHub
Releases may contain a separate database-only Full OTA asset when the
repository owner has independently confirmed the right to distribute every
included data source. That confirmation does not grant downstream recipients a
license to extract or redistribute the underlying dictionary sources.

The `data/*.tsv` files contain only a small set of independently reviewed
maintenance corrections, not the source dictionary or a usable database. The
Python maintenance tools require database, StarDict, WordNet and OMW inputs to
be supplied separately. WordNet/OMW alignment is used to produce an audit
queue; RC1.3.1 does not automatically publish those suggested translations.

The Full OTA updater accepts only a separate package containing the three
dictionary databases, a manifest and a README. It rejects `known_words.db`,
book sidecars/settings and all unknown archive paths.
