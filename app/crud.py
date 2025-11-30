from sqlalchemy.orm import Session
from app import models


def create_note(db: Session, text: str):
    db_note = models.Note(text=text)
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    return db_note


def get_notes(db: Session):
    return db.query(models.Note).all()


def get_note_by_id(db: Session, note_id: int):
    return db.query(models.Note).filter(models.Note.id == note_id).first()


def update_note(db: Session, note_id: int, text: str):
    note = db.query(models.Note).filter(models.Note.id == note_id).first()
    if note:
        note.text = text
        db.commit()
        db.refresh(note)
    return note


def delete_note(db: Session, note_id: int):
    note = db.query(models.Note).filter(models.Note.id == note_id).first()
    if note:
        db.delete(note)
        db.commit()
    return note
