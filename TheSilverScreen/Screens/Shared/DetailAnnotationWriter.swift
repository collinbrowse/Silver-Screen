//
//  DetailAnnotationWriter.swift
//  TheSilverScreen
//
//  Shared annotation writes for detail screens that do not couple rating to
//  Watched. Movie detail wraps `save` with its own Watched rollback.
//

import Foundation

@MainActor
enum DetailAnnotationWriter {
    /// Opens the combined editor from the personal values already on screen.
    static func session(title: String, score: Double?, note: String?) -> AnnotationEditorSession {
        AnnotationEditorSession(
            title: title,
            score: score,
            note: note ?? "",
            canDeleteNote: note != nil,
            hasExistingScore: score != nil
        )
    }

    static func save(
        score: Double,
        note: String,
        for key: AnnotationKey,
        annotations: AnnotationsRepository
    ) async -> (AnnotationEditorWriteResult, MediaAnnotation?) {
        do {
            let saved = try await annotations.save(score: score, note: note, for: key)
            return (.succeeded, saved)
        } catch is CancellationError {
            return (.cancelled, nil)
        } catch {
            return (.failed, nil)
        }
    }

    static func deleteNote(
        for key: AnnotationKey,
        annotations: AnnotationsRepository
    ) async -> (AnnotationEditorWriteResult, MediaAnnotation?) {
        do {
            let saved = try await annotations.deleteNote(for: key)
            return (.succeeded, saved)
        } catch is CancellationError {
            return (.cancelled, nil)
        } catch {
            return (.failed, nil)
        }
    }

    static func clear(
        for key: AnnotationKey,
        annotations: AnnotationsRepository
    ) async -> AnnotationEditorWriteResult {
        do {
            try await annotations.clear(for: key)
            return .succeeded
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
    }
}
